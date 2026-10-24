export namespace session {

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
	    category: string;

	    static createFrom(source: any = {}) {
	        return new Classification(source);
	    }

	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.category = source["category"];
	    }
	}
	export class Task {
	    id: string;
	    name: string;
	    plannedSeconds: number;
	    minimumSeconds: number;

	    static createFrom(source: any = {}) {
	        return new Task(source);
	    }

	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.plannedSeconds = source["plannedSeconds"];
	        this.minimumSeconds = source["minimumSeconds"];
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
	export class Result {
	    sessionId: string;
	    name: string;
	    status: string;
	    elapsedSeconds: number;
	    workSeconds: number;
	    distractedSeconds: number;
	    uncertainSeconds: number;
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
	        this.workSeconds = source["workSeconds"];
	        this.distractedSeconds = source["distractedSeconds"];
	        this.uncertainSeconds = source["uncertainSeconds"];
	        this.earnedSeconds = source["earnedSeconds"];
	        this.usedSeconds = source["usedSeconds"];
	        this.discardedSeconds = source["discardedSeconds"];
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
	export class WorkSession {
	    id: string;
	    name: string;
	    status: string;
	    task: Task;
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
	    restrictionDesired: string;
	    restrictionConfirmed: boolean;
	    settings: Settings;
	    history: Result[];
	    result?: Result;
	    actions: Record<string, Capability>;
	    failure?: Failure;

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
	        this.restrictionDesired = source["restrictionDesired"];
	        this.restrictionConfirmed = source["restrictionConfirmed"];
	        this.settings = this.convertValues(source["settings"], Settings);
	        this.history = this.convertValues(source["history"], Result);
	        this.result = this.convertValues(source["result"], Result);
	        this.actions = this.convertValues(source["actions"], Capability, true);
	        this.failure = this.convertValues(source["failure"], Failure);
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
