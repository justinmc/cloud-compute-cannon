package ccc.compute.server.tests;

import ccc.compute.workers.WorkerProviderPkgCloud;

import cloud.MachineMonitor;

import js.npm.PkgCloud;
import js.npm.ssh2.Ssh;

import promhx.deferred.*;

import util.SshTools;

using Lambda;

class TestWorkerMonitoring extends haxe.unit.async.PromiseTest
{
	var _config :ServiceConfigurationWorkerProvider;

	public function new()
	{
		//Get the ServerConfig is available
		var serviceConfig = InitConfigTools.getConfig();
		if (serviceConfig != null) {
			_config = serviceConfig.providers[0];
		}
	}

	@timeout(1200000)//20min
	/**
	 * Parallelize these tests for speed
	 * @return [description]
	 */
	public function testWorkerMonitor() :Promise<Bool>
	{
		var promises = [_testWorkerDockerMonitor(), _testWorkerDiskFull()];

		return Promise.whenAll(promises)
			.then(function(results) {
				return !results.exists(function(e) return !e);
			});
	}

	@timeout(10000)//10s
	/**
	 * Workers that do not exist should fail correctly
	 */
	public function testWorkerMissingOnStartup() :Promise<Bool>
	{
		var promise = new DeferredPromise();
		var monitor = new MachineMonitor()
			.monitorDocker({host: 'fakehost', port: 2375, protocol: 'http'});
		monitor.status.then(function(status) {
			switch(status) {
				case Connecting:
				case OK:
					if (promise != null) {
						promise.boundPromise.reject('Wrong status=${status}, should never be OK since the machine does not exist');
						promise = null;
					}
				case CriticalFailure(failure):
					assertEquals(failure, MachineFailureType.DockerConnectionLost);
					if (promise != null) {
						promise.resolve(true);
						promise = null;
					}
			}
		});
		return promise.boundPromise;
	}

	/**
	 * Creates a fake worker, monitors it, and then proceeds to
	 * fill up the disk. It should register as failed when the
	 * disk reaches a given capacity.
	 */
	@timeout(1200000)//20min
	//This test can run in parallel to others
	public function _testWorkerDockerMonitor() :Promise<Bool>
	{
		if (_config == null || _config.type != ServiceWorkerProviderType.pkgcloud) {
			traceYellow('Cannot run ${Type.getClassName(Type.getClass(this)).split('.').pop()}.testWorkerDockerMonitor: no configuration for a real cloud provider');
			return Promise.promise(true);
		} else if (!_config.machines.exists('test')) {
			traceYellow('Cannot run ${Type.getClassName(Type.getClass(this)).split('.').pop()}.testWorkerDockerMonitor: missing worker definition "test"');
			return Promise.promise(true);
		} else {
			return testWorkerMonitorDockerPing(_config);
		}
	}

	@timeout(1200000)//20min
	//This test can run in parallel to others
	public function _testWorkerDiskFull() :Promise<Bool>
	{
		if (_config == null || _config.type != ServiceWorkerProviderType.pkgcloud) {
			traceYellow('Cannot run ${Type.getClassName(Type.getClass(this)).split('.').pop()}.testWorkerDiskFull: no configuration for a real cloud provider');
			return Promise.promise(true);
		} else if (!_config.machines.exists('test')) {
			traceYellow('Cannot run ${Type.getClassName(Type.getClass(this)).split('.').pop()}.testWorkerDiskFull: missing worker definition "test"');
			return Promise.promise(true);
		} else {
			return testWorkerMonitorDiskCapacity(_config);
		}
	}

	static function testWorkerMonitorDockerPing(config :ServiceConfigurationWorkerProvider) :Promise<Bool>
	{
		var machineType = 'test';
		var monitor :MachineMonitor;
		var instanceDef :InstanceDefinition;

		return Promise.promise(true)
			.pipe(function(_) {
				return WorkerProviderPkgCloud.createInstance(config, machineType);
			})
			.pipe(function(def) {
				instanceDef = def;
				var promise = new DeferredPromise();
				monitor = new MachineMonitor()
					.monitorDocker(instanceDef.docker, 1000, 3, 1000);
				monitor.status.then(function(status) {
					switch(status) {
						case Connecting:
						case OK:
							if (promise != null) {
								promise.resolve(status);
								promise = null;
							}
						case CriticalFailure(failure):
							if (promise != null) {
								promise.boundPromise.reject(failure);
								promise = null;
							}
					}
				});
				return promise.boundPromise;
			})
			.pipe(function(status) {
				//Now kill the machine, and the listen for the failure
				var promise = new DeferredPromise<Bool>();
				var gotFailure = false;
				var shutdown = false;
				monitor.status.then(function(state) {
					switch(state) {
						case Connecting,OK:
						case CriticalFailure(failureType):
							switch(failureType) {
								case DockerConnectionLost:
									if (promise != null) {
										gotFailure = true;
										promise.resolve(true);
										promise = null;
									}
								default:
									if (promise != null) {
										promise.boundPromise.reject('Wrong failure type: $failureType');
										promise = null;
									}
							}
					}
				});
				WorkerProviderPkgCloud.destroyCloudInstance(config, instanceDef.id)
					.then(function(_) {
						shutdown = true;
						js.Node.setTimeout(function() {
							if (!gotFailure && promise != null) {
								promise.boundPromise.reject('Timeout waiting on induced docker failure, failed to detect it');
								promise = null;
							}
						}, 30000);//30s, plenty of time
					});

				return promise.boundPromise;
			})
			.errorPipe(function(err) {
				traceRed(err);
				return WorkerProviderPkgCloud.destroyCloudInstance(config, instanceDef.id)
					.then(function(_) {
						return false;
					})
					.errorPipe(function(err) {
						traceRed(err);
						return Promise.promise(false);
					});
			});
	}

	static function testWorkerMonitorDiskCapacity(config :ServiceConfigurationWorkerProvider) :Promise<Bool>
	{
		var machineType = 'test';
		var monitor :MachineMonitor;
		var instanceDef :InstanceDefinition;

		return Promise.promise(true)
			.pipe(function(_) {
				return WorkerProviderPkgCloud.createInstance(config, machineType);
			})
			.pipe(function(def) {
				instanceDef = def;
				var promise = new DeferredPromise();
				monitor = new MachineMonitor()
					.monitorDiskSpace(instanceDef.ssh, 0.2, 1000, 3, 1000);
				monitor.status.then(function(status) {
					switch(status) {
						case Connecting:
						case OK:
							if (promise != null) {
								promise.resolve(status);
								promise = null;
							}
						case CriticalFailure(failure):
							if (promise != null) {
								promise.boundPromise .reject(failure);
								promise = null;
							}
					}
				});
				return promise.boundPromise;
			})
			.pipe(function(status) {
				//Now fill up disk space, and the listen for the failure
				var promise = new DeferredPromise<Bool>();
				var gotFailure = false;
				// var shutdown = false;
				monitor.status.then(function(state) {
					switch(state) {
						case Connecting,OK:
						case CriticalFailure(failureType):
							switch(failureType) {
								case DiskCapacityCritical:
									if (promise != null) {
										gotFailure = true;
										promise.resolve(true);
										promise = null;
									}
								default:
									if (promise != null) {
										promise.boundPromise.reject('Wrong failure type: $failureType');
										promise = null;
									}
							}
					}
				});
				var addSpace = null;
				var addSpaceCount = 1;
				addSpace = function() {
					createFile(instanceDef.ssh, '/blob${addSpaceCount++}', 1000)
						.then(function(out) {
							if (!gotFailure && promise != null) {
								addSpace();
							}
						});
				}
				addSpace();

				return promise.boundPromise
					//But always destroy this machine when the test is done
					.pipe(function(result) {
						return WorkerProviderPkgCloud.destroyCloudInstance(config, instanceDef.id)
							.then(function(_) {
								return result;
							})
							.errorPipe(function(err) {
								traceRed(err);
								return Promise.promise(result);
							});
					});
			})
			.errorPipe(function(err) {
				traceRed(err);
				return WorkerProviderPkgCloud.destroyCloudInstance(config, instanceDef.id)
					.then(function(_) {
						return false;
					})
					.errorPipe(function(err) {
						traceRed(err);
						return Promise.promise(false);
					});
			});
	}

	static function createFile(ssh :ConnectOptions, path :String, sizeMb :Int = 1) :Promise<Bool>
	{
		return SshTools.execute(ssh, 'sudo dd if=/dev/zero of=$path count=$sizeMb bs=1048576', 1)
			.then(function(out) {
				return out.code == 0;
			});
	}
}