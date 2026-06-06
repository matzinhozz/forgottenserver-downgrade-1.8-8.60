// Copyright 2023 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#include "otpch.h"

#include "reactor.h"

#include "stats.h"

TaskReactor g_reactor;

namespace {
auto distantFuture() noexcept
{
	return std::chrono::steady_clock::time_point::max();
}
} // namespace

bool TaskReactor::Task::hasExpired(std::chrono::steady_clock::time_point now) const noexcept
{
	return deadline != distantFuture() && deadline < now;
}

void TaskReactor::start() noexcept
{
	threadState.store(THREAD_STATE_RUNNING, std::memory_order_relaxed);
}

void TaskReactor::send(ReactorCallback&& callback)
{
	send(0, std::move(callback));
}

void TaskReactor::send(uint32_t expirationTime, ReactorCallback&& callback)
{
	if (!callback || threadState.load(std::memory_order_relaxed) == THREAD_STATE_TERMINATED) {
		return;
	}

	const auto now = std::chrono::steady_clock::now();
	Task task{
	    .fireAt = now,
	    .deadline = expirationTime == 0 ? distantFuture() : now + std::chrono::milliseconds(expirationTime),
	    .sequence = nextSequence.fetch_add(1, std::memory_order_relaxed),
	    .function = std::move(callback),
	};

	{
		std::scoped_lock lock(mutex);
		sendInbox.push_back(std::move(task));
	}

	conditionVariable.notify_one();
}

uint32_t TaskReactor::schedule(uint32_t delay, ReactorCallback&& callback)
{
	if (!callback || threadState.load(std::memory_order_relaxed) == THREAD_STATE_TERMINATED) {
		return 0;
	}

	uint32_t identifier = nextIdentifier.fetch_add(1, std::memory_order_relaxed) + 1;
	if (identifier == 0) {
		identifier = nextIdentifier.fetch_add(1, std::memory_order_relaxed) + 1;
	}

	Task task{
	    .fireAt = std::chrono::steady_clock::now() + std::chrono::milliseconds(delay),
	    .deadline = distantFuture(),
	    .identifier = identifier,
	    .sequence = nextSequence.fetch_add(1, std::memory_order_relaxed),
	    .function = std::move(callback),
	};

	{
		std::scoped_lock lock(mutex);
		scheduleInbox.push_back(std::move(task));
	}

	conditionVariable.notify_one();
	return identifier;
}

void TaskReactor::cancel(uint32_t taskIdentifier)
{
	if (taskIdentifier == 0) {
		return;
	}

	{
		std::scoped_lock lock(mutex);
		cancelInbox.push_back(taskIdentifier);
	}

	conditionVariable.notify_one();
}

void TaskReactor::runLoop()
{
	reactorThreadId = std::this_thread::get_id();

	while (threadState.load(std::memory_order_relaxed) != THREAD_STATE_TERMINATED) {
		runOnce();

		if (threadState.load(std::memory_order_relaxed) == THREAD_STATE_TERMINATED) {
			break;
		}

		waitForWork();
	}
}

void TaskReactor::runOnce()
{
	std::vector<Task> readyTasks;
	readyTasks.reserve(128);

	drainInbox(readyTasks);
	drainReadyTasks(readyTasks);
	executeReadyTasks(readyTasks);
}

void TaskReactor::shutdown() noexcept
{
	threadState.store(THREAD_STATE_TERMINATED, std::memory_order_relaxed);
	conditionVariable.notify_one();
}

bool TaskReactor::isReactorThread() const noexcept
{
	return reactorThreadId == std::this_thread::get_id();
}

ThreadState TaskReactor::getState() const noexcept
{
	return threadState.load(std::memory_order_relaxed);
}

bool TaskReactor::taskComesAfter(const Task& lhs, const Task& rhs) noexcept
{
	if (lhs.fireAt != rhs.fireAt) {
		return lhs.fireAt > rhs.fireAt;
	}
	return lhs.sequence > rhs.sequence;
}

void TaskReactor::drainInbox(std::vector<Task>& readyTasks)
{
	std::vector<Task> sentTasks;
	std::vector<Task> scheduledTasks;
	std::vector<uint32_t> cancellations;

	{
		std::scoped_lock lock(mutex);
		sentTasks.swap(sendInbox);
		scheduledTasks.swap(scheduleInbox);
		cancellations.swap(cancelInbox);
	}

	for (auto& task : scheduledTasks) {
		activeIdentifiers.insert(task.identifier);
		taskHeap.push_back(std::move(task));
		std::push_heap(taskHeap.begin(), taskHeap.end(), taskComesAfter);
	}

	for (uint32_t identifier : cancellations) {
		if (activeIdentifiers.contains(identifier)) {
			cancelled.insert(identifier);
		}
	}

	const auto now = std::chrono::steady_clock::now();
	for (auto& task : sentTasks) {
		if (!task.hasExpired(now)) {
			readyTasks.push_back(std::move(task));
		}
	}
}

void TaskReactor::drainReadyTasks(std::vector<Task>& readyTasks)
{
	const auto now = std::chrono::steady_clock::now();

	while (!taskHeap.empty() && taskHeap.front().fireAt <= now) {
		std::pop_heap(taskHeap.begin(), taskHeap.end(), taskComesAfter);
		auto readyTask = std::move(taskHeap.back());
		taskHeap.pop_back();

		activeIdentifiers.erase(readyTask.identifier);
		if (cancelled.erase(readyTask.identifier) > 0 || readyTask.hasExpired(now)) {
			continue;
		}

		readyTasks.push_back(std::move(readyTask));
	}
}

void TaskReactor::executeReadyTasks(std::vector<Task>& readyTasks)
{
	std::sort(readyTasks.begin(), readyTasks.end(), [](const Task& lhs, const Task& rhs) {
		if (lhs.fireAt != rhs.fireAt) {
			return lhs.fireAt < rhs.fireAt;
		}
		return lhs.sequence < rhs.sequence;
	});

	for (auto& task : readyTasks) {
		if (task.function) {
			task.function();
		}
	}
}

void TaskReactor::waitForWork()
{
	auto timeout = std::chrono::milliseconds(100);

	if (!taskHeap.empty()) {
		const auto now = std::chrono::steady_clock::now();
		if (taskHeap.front().fireAt > now) {
			timeout = std::chrono::duration_cast<std::chrono::milliseconds>(taskHeap.front().fireAt - now);
		} else {
			timeout = std::chrono::milliseconds::zero();
		}
	}

#ifdef STATS_ENABLED
	const auto waitStart = std::chrono::steady_clock::now();
#endif
	auto wakePredicate = [this]() {
		return threadState.load(std::memory_order_relaxed) == THREAD_STATE_TERMINATED || !sendInbox.empty() ||
		       !scheduleInbox.empty() || !cancelInbox.empty();
	};

	std::unique_lock lock(mutex);
	conditionVariable.wait_for(lock, timeout, wakePredicate);
	lock.unlock();

#ifdef STATS_ENABLED
	if (g_stats.isEnabled() && g_stats.isRunning()) {
		const auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(
		    std::chrono::steady_clock::now() - waitStart).count();
		g_stats.addDispatcherWaitTime(0, elapsed > 0 ? static_cast<uint64_t>(elapsed) : 0);
	}
#endif
}
