package ccc.compute;

import js.npm.RedisClient;

import promhx.RedisPromises;

@:enum
abstract JobStatsLog(String) to String from String {
	var Submitted = 'submitted';
	var Dequeued = 'dequeued';
	var BeganWorking = 'began_working';
	var CopiedInputs = 'copied_inputs';
	var CopiedImage = 'copied_image';
	var CopiedInputsAndImage = 'copied_inputs_and_image';
	var ContainerFinished = 'container_finished';
	var CopiedLogs = 'copied_logs';
	var CopiedOutputs = 'copied_outputs';
	var CopiedLogsAndOutputs = 'copied_logs_and_outputs';
	var Finished = 'finished';
}

class JobStatsLogger
{
	inline static var PREFIX = 'compute_stats${Constants.SEP}';

	public static function setStateTime(redis :RedisClient, jobId :JobId, status :JobStatsLog, ?date :Date) :Promise<Bool>
	{
		if (date == null) {
			date = Date.now();
		}
		Log.debug({jobstatslog:{jobid:jobId, status:status, date.toString()}});
		return RedisPromises.hset(redis, PREFIX + status, jobId, date.getTime())
			//Log the error but do not kill the process just because this failed
			.errorPipe(function(err) {
				Log.error({error:err, message:'JobStatsLogger.setStateTime', jobId:jobId, status:status, date:date});
				return Promise.promise(false);
			});
	}
}