import { MiniAppError } from '../MiniAppError';
import { SESSION_ALREADY_ATTACHED_OR_CLOSED } from '../MiniAppErrorCode';
import { SdkLogger } from '../../logging/SdkLogger';
import { MiniAppLifecycle, MiniAppLifecycleChange, MiniAppLifecycleState } from './MiniAppLifecycle';

interface LifecycleBinding {
  readonly lifecycle: MiniAppSessionLifecycle;
  select?: (active: boolean) => void;
  claimed: boolean;
}

enum LifecycleInputKind {
  SELECT,
  HOST_FOREGROUND,
  ATTACH,
  DESTROY
}

interface LifecycleInput {
  kind: LifecycleInputKind;
  value?: boolean;
}

const bindings: WeakMap<MiniAppLifecycleController, LifecycleBinding> = new WeakMap();

/** 宿主选中意图与只读生命周期句柄；一个控制器只能用于一次挂载。 */
export class MiniAppLifecycleController implements MiniAppLifecycle {
  constructor(initiallyActive: boolean = true) {
    new MiniAppSessionLifecycle(this, initiallyActive);
  }

  activate(): void {
    bindings.get(this)?.select?.(true);
  }

  deactivate(): void {
    bindings.get(this)?.select?.(false);
  }

  getState(): MiniAppLifecycleState {
    return bindings.get(this)!.lifecycle.getState();
  }

  isForeground(): boolean {
    return this.getState() === MiniAppLifecycleState.FOREGROUND;
  }

  observe(listener: (change: MiniAppLifecycleChange) => void): () => void {
    return bindings.get(this)!.lifecycle.observe(listener);
  }
}

/** Session 独占的内部输入端口，不由 HAR 入口导出。 */
export class MiniAppSessionLifecycle implements MiniAppLifecycle {
  private state: MiniAppLifecycleState = MiniAppLifecycleState.CREATED;
  private selected: boolean;
  private hostForeground: boolean = false;
  private attached: boolean = false;
  private dispatching: boolean = false;
  private inputs: LifecycleInput[] = [];
  private observers: Map<number, (change: MiniAppLifecycleChange) => void> = new Map();
  private nextObserverId: number = 0;
  private binding: LifecycleBinding;

  /** 仅由控制器创建；闭包将选中输入留在模块内部。 */
  constructor(controller: MiniAppLifecycleController, initiallyActive: boolean) {
    this.selected = initiallyActive;
    this.binding = {
      lifecycle: this,
      select: (active: boolean): void => {
        this.enqueue({ kind: LifecycleInputKind.SELECT, value: active });
      },
      claimed: false
    };
    bindings.set(controller, this.binding);
  }

  getState(): MiniAppLifecycleState {
    return this.state;
  }

  isForeground(): boolean {
    return this.state === MiniAppLifecycleState.FOREGROUND;
  }

  observe(listener: (change: MiniAppLifecycleChange) => void): () => void {
    if (this.state === MiniAppLifecycleState.DESTROYED) {
      return (): void => {};
    }
    const id = this.nextObserverId++;
    this.observers.set(id, listener);
    return (): void => {
      this.observers.delete(id);
    };
  }

  setAttached(): void {
    this.enqueue({ kind: LifecycleInputKind.ATTACH });
  }

  setHostForeground(foreground: boolean): void {
    this.enqueue({ kind: LifecycleInputKind.HOST_FOREGROUND, value: foreground });
  }

  destroy(): void {
    this.enqueue({ kind: LifecycleInputKind.DESTROY });
  }

  private enqueue(input: LifecycleInput): void {
    if (this.state === MiniAppLifecycleState.DESTROYED) {
      return;
    }
    this.inputs.push(input);
    if (this.dispatching) {
      return;
    }
    this.dispatching = true;
    try {
      while (this.inputs.length > 0 && this.getState() !== MiniAppLifecycleState.DESTROYED) {
        const next = this.inputs.shift();
        if (next) {
          this.apply(next);
        }
      }
    } finally {
      this.dispatching = false;
    }
  }

  private apply(input: LifecycleInput): void {
    if (input.kind === LifecycleInputKind.SELECT) {
      this.selected = input.value === true;
    } else if (input.kind === LifecycleInputKind.HOST_FOREGROUND) {
      this.hostForeground = input.value === true;
    } else if (input.kind === LifecycleInputKind.ATTACH) {
      this.attached = true;
    }
    let current: MiniAppLifecycleState = MiniAppLifecycleState.CREATED;
    if (input.kind === LifecycleInputKind.DESTROY) {
      current = MiniAppLifecycleState.DESTROYED;
    } else if (this.attached) {
      current = this.selected && this.hostForeground ?
        MiniAppLifecycleState.FOREGROUND : MiniAppLifecycleState.BACKGROUND;
    }
    if (current === this.state) {
      return;
    }
    const change: MiniAppLifecycleChange = { previous: this.state, current };
    this.state = current;
    const observers = Array.from(this.observers.entries());
    for (const entry of observers) {
      if (!this.observers.has(entry[0])) {
        continue;
      }
      try {
        entry[1](change);
      } catch (_) {
        SdkLogger.warn('MiniAppLifecycle', 'observer_failed');
      }
    }
    if (current === MiniAppLifecycleState.DESTROYED) {
      this.observers.clear();
      this.inputs = [];
      this.binding.select = undefined;
    }
  }
}

/** 在创建厂商 Binding 前领取一次，失败时不改变已绑定会话。 */
export function bindMiniAppLifecycle(controller: MiniAppLifecycleController): MiniAppSessionLifecycle {
  const binding = bindings.get(controller);
  if (!binding || binding.claimed || binding.lifecycle.getState() === MiniAppLifecycleState.DESTROYED) {
    throw new MiniAppError(SESSION_ALREADY_ATTACHED_OR_CLOSED, '生命周期控制器已绑定会话或已经关闭');
  }
  binding.claimed = true;
  return binding.lifecycle;
}
