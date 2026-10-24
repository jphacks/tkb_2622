export namespace monitor {

	export class ClassificationCandidate {
	    name: string;
	    appId: string;
	    appName: string;
	    domain: string;
	    sampleCount: number;

	    static createFrom(source: any = {}) {
	        return new ClassificationCandidate(source);
	    }

	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.appId = source["appId"];
	        this.appName = source["appName"];
	        this.domain = source["domain"];
	        this.sampleCount = source["sampleCount"];
	    }
	}

}

export namespace session {

	export class AccountState {
	    status: string;
	    email: string;
	    deviceRegistered: boolean;
	    message: string;

	    static createFrom(source: any = {}) {
	        return new AccountState(source);
	    }

	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.status = source["status"];
	        this.email = source["email"];
	        this.deviceRegistered = source["deviceRegistered"];
	        this.message = source["message"];
	    }
	}
	export class Capability {
	    allowed: boolean;
	    reason: string;

	    static createFrom(source: any = {}) {
	        return new Capability(source);
	    }

	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.allowed = source["allowed"];
	        this.reason = source["reason"];
	    }
	}
	export class Classification {
	    name: string;
	    appId?: string;
	    domain?: string;
	    category: string;

	    static createFrom(source: any = {}) {
	        return new Classification(source);
	    }

	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.appId = source["appId"];
	        this.domain = source["domain"];
	        this.category = source["category"];
	    }
	}
	export class Settings {
	    tasks: Task[];
	    selectedTaskId: string;
	    classifications: Classification[];

	    static createFrom(source: any = {}) {
	        return new Settings(source);
	    }

	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.tasks = this.convertValues(source["tasks"], Task);
	        this.selectedTaskId = source["selectedTaskId"];
	        this.classifications = this.convertValues(source["classifications"], Classification);
	    }

		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class Task {
	    id: string;
	    name: string;
	    category: string;
	    mode: string;
	    plannedSeconds: number;
	    minimumSeconds: number;
	    version: number;
	    pendingOperationId?: string;
	    pendingSettingsHash?: string;

	    static createFrom(source: any = {}) {
	        return new Task(source);
	    }

	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.category = source["category"];
	        this.mode = source["mode"];
	        this.plannedSeconds = source["plannedSeconds"];
	        this.minimumSeconds = source["minimumSeconds"];
	        this.version = source["version"];
	        this.pendingOperationId = source["pendingOperationId"];
	        this.pendingSettingsHash = source["pendingSettingsHash"];
	    }
	}
	export class Command {
	    action: string;
	    name: string;
	    scenarioId: string;
	    task: Task;
	    classification: Classification;
	    settings: Settings;

	    static createFrom(source: any = {}) {
	        return new Command(source);
	    }

	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.action = source["action"];
	        this.name = source["name"];
	        this.scenarioId = source["scenarioId"];
	        this.task = this.convertValues(source["task"], Task);
	        this.classification = this.convertValues(source["classification"], Classification);
	        this.settings = this.convertValues(source["settings"], Settings);
	    }

		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class Failure {
	    code: string;
	    message: string;
	    retryable: boolean;

	    static createFrom(source: any = {}) {
	        return new Failure(source);
	    }

	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.code = source["code"];
	        this.message = source["message"];
	        this.retryable = source["retryable"];
	    }
	}
	export class MonitorStatus {
	    state: string;
	    appId: string;
	    appName: string;
	    browserName: string;
	    domain: string;
	    lastSample: string;
	    sampleCount: number;
	    message: string;

	    static createFrom(source: any = {}) {
	        return new MonitorStatus(source);
	    }

	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.state = source["state"];
	        this.appId = source["appId"];
	        this.appName = source["appName"];
	        this.browserName = source["browserName"];
	        this.domain = source["domain"];
	        this.lastSample = source["lastSample"];
	        this.sampleCount = source["sampleCount"];
	        this.message = source["message"];
	    }
	}
	export class Result {
	    sessionId: string;
	    name: string;
	    status: string;
	    elapsedSeconds: number;
	    taskSeconds: number;
	    relatedSeconds: number;
	    workSeconds: number;
	    distractedSeconds: number;
	    uncertainSeconds: number;
	    inactiveSeconds: number;
	    evaluatorVersion?: string;
	    earnedSeconds: number;
	    usedSeconds: number;
	    discardedSeconds: number;

	    static createFrom(source: any = {}) {
	        return new Result(source);
	    }

	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.sessionId = source["sessionId"];
	        this.name = source["name"];
	        this.status = source["status"];
	        this.elapsedSeconds = source["elapsedSeconds"];
	        this.taskSeconds = source["taskSeconds"];
	        this.relatedSeconds = source["relatedSeconds"];
	        this.workSeconds = source["workSeconds"];
	        this.distractedSeconds = source["distractedSeconds"];
	        this.uncertainSeconds = source["uncertainSeconds"];
	        this.inactiveSeconds = source["inactiveSeconds"];
	        this.evaluatorVersion = source["evaluatorVersion"];
	        this.earnedSeconds = source["earnedSeconds"];
	        this.usedSeconds = source["usedSeconds"];
	        this.discardedSeconds = source["discardedSeconds"];
	    }
	}

	export class WorkSession {
	    id: string;
	    name: string;
	    status: string;
	    task: Task;
	    classifications?: Classification[];
	    rulesVersion?: string;
	    elapsedSeconds: number;
	    evaluation: string;

	    static createFrom(source: any = {}) {
	        return new WorkSession(source);
	    }

	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.status = source["status"];
	        this.task = this.convertValues(source["task"], Task);
	        this.classifications = this.convertValues(source["classifications"], Classification);
	        this.rulesVersion = source["rulesVersion"];
	        this.elapsedSeconds = source["elapsedSeconds"];
	        this.evaluation = source["evaluation"];
	    }

		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class Snapshot {
	    revision: number;
	    platform: string;
	    mode: string;
	    updatedAt: string;
	    session?: WorkSession;
	    balanceSeconds?: number;
	    sync: string;
	    permission: string;
	    online: boolean;
	    monitor: MonitorStatus;
	    restrictionDesired: string;
	    restrictionConfirmed: boolean;
	    settings: Settings;
	    history: Result[];
	    result?: Result;
	    actions: Record<string, Capability>;
	    failure?: Failure;
	    account: AccountState;

	    static createFrom(source: any = {}) {
	        return new Snapshot(source);
	    }

	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.revision = source["revision"];
	        this.platform = source["platform"];
	        this.mode = source["mode"];
	        this.updatedAt = source["updatedAt"];
	        this.session = this.convertValues(source["session"], WorkSession);
	        this.balanceSeconds = source["balanceSeconds"];
	        this.sync = source["sync"];
	        this.permission = source["permission"];
	        this.online = source["online"];
	        this.monitor = this.convertValues(source["monitor"], MonitorStatus);
	        this.restrictionDesired = source["restrictionDesired"];
	        this.restrictionConfirmed = source["restrictionConfirmed"];
	        this.settings = this.convertValues(source["settings"], Settings);
	        this.history = this.convertValues(source["history"], Result);
	        this.result = this.convertValues(source["result"], Result);
	        this.actions = this.convertValues(source["actions"], Capability, true);
	        this.failure = this.convertValues(source["failure"], Failure);
	        this.account = this.convertValues(source["account"], AccountState);
	    }

		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}


}

