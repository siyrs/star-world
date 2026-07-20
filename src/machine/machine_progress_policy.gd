class_name MachineProgressPolicy
extends RefCounted

const EPSILON := 0.0001


static func normalize_elapsed(seconds: float, maximum_seconds: float) -> float:
	var safe_maximum := maxf(0.0, maximum_seconds)
	if not is_finite(seconds):
		return 0.0
	return clampf(seconds, 0.0, safe_maximum)


static func progress_ratio(progress_seconds: float, duration_seconds: float) -> float:
	var duration := maxf(EPSILON, duration_seconds)
	return clampf(maxf(0.0, progress_seconds) / duration, 0.0, 1.0)


static func remaining_seconds(progress_seconds: float, duration_seconds: float) -> float:
	var duration := maxf(EPSILON, duration_seconds)
	return maxf(0.0, duration - clampf(progress_seconds, 0.0, duration))


static func queued_jobs(
	input_count: int,
	input_per_job: int,
	output_count: int,
	current_output_count: int,
	maximum_output_count: int
) -> int:
	var required_input := maxi(1, input_per_job)
	var produced_per_job := maxi(1, output_count)
	var input_jobs := floori(float(maxi(0, input_count)) / float(required_input))
	var free_output := maxi(0, maximum_output_count - maxi(0, current_output_count))
	var output_jobs := floori(float(free_output) / float(produced_per_job))
	return maxi(0, mini(input_jobs, output_jobs))


static func queued_output_count(job_count: int, output_count: int) -> int:
	return maxi(0, job_count) * maxi(1, output_count)


static func estimated_total_seconds(
	progress_seconds: float, duration_seconds: float, job_count: int
) -> float:
	if job_count <= 0:
		return 0.0
	var duration := maxf(EPSILON, duration_seconds)
	return remaining_seconds(progress_seconds, duration) + duration * float(job_count - 1)
