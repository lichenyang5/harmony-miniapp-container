import { LineAccountManager } from './LineAccountManager';
import { LineLoginController } from './LineLoginController';
import { LineLoginPresenter, LineLoginRequest, LineLoginState } from './LineLoginTypes';
import { MiniAppError } from '../../../core/MiniAppError';
import { LineErrorCode } from '../LineErrorCode';
import { LineAccountUiLease, LineAccountUiOwner } from './LineAccountUiLease';
import { LinePhoneRegistrationSession } from '../registration/LinePhoneRegistrationSession';
import { LinePhoneRegistrationState } from '../registration/LineRegistrationSessionTypes';
import { LineRegistrationPresenter, LineRegistrationRequest } from '../registration/LineRegistrationUiTypes';

class LineLoginWaiter {
  readonly result: Promise<void>;
  readonly reuseOnly: boolean;
  readonly registration: boolean;
  resolve: () => void = (): void => {};
  reject: (error: MiniAppError) => void = (_error: MiniAppError): void => {};
  constructor(reuseOnly: boolean, registration: boolean) {
    this.reuseOnly = reuseOnly;
    this.registration = registration;
    this.result = new Promise<void>((resolve, reject): void => { this.resolve = resolve; this.reject = reject; });
  }
}


class LineLoginFlow {
  readonly owner: LineAccountUiOwner;
  readonly waiters: Set<LineLoginWaiter> = new Set<LineLoginWaiter>();
  readonly presenter?: LineLoginPresenter;
  readonly registrationPresenter?: LineRegistrationPresenter;
  controller?: LineLoginController;
  session?: LinePhoneRegistrationSession;
  presentation?: LineLoginPresenter | LineRegistrationPresenter;
  showing?: Promise<void>;
  closing: boolean = false;
  mode: 'login' | 'registration' | 'switching';
  generation: number = 0;
  constructor(owner: LineAccountUiOwner, presenter?: LineLoginPresenter, registration?: LineRegistrationPresenter) {
    this.owner = owner;
    this.presenter = presenter;
    this.registrationPresenter = registration;
    this.mode = registration ? 'registration' : 'login';
  }
}

/** One account flow, including idle forms, belongs to its first requesting ability. */
export class LineLoginCoordinator {
  private static readonly coordinators: WeakMap<LineAccountManager, LineLoginCoordinator> = new WeakMap<LineAccountManager, LineLoginCoordinator>();
  private readonly account: LineAccountManager;
  private flow?: LineLoginFlow;
  private constructor(account: LineAccountManager) { this.account = account; }

  static forAccount(account: LineAccountManager): LineLoginCoordinator {
    let coordinator = LineLoginCoordinator.coordinators.get(account);
    if (!coordinator) { coordinator = new LineLoginCoordinator(account); LineLoginCoordinator.coordinators.set(account, coordinator); }
    return coordinator;
  }

  request(presenter: LineLoginPresenter, reuseOnly: boolean = false): LineLoginRequest {
    return this.join(presenter, undefined, reuseOnly);
  }

  requestRegistration(presenter: LineRegistrationPresenter): LineRegistrationRequest {
    return this.join(undefined, presenter, false);
  }

  private join(presenter?: LineLoginPresenter, registration?: LineRegistrationPresenter, reuseOnly: boolean = false): LineLoginRequest {
    const waiter = new LineLoginWaiter(reuseOnly, registration !== undefined);
    let flow = this.flow;
    const context = presenter?.context ?? registration?.context;
    const ownerContext = flow?.presenter?.context ?? flow?.registrationPresenter?.context;
    let failure: MiniAppError | undefined;
    if (flow && reuseOnly && (flow.controller || flow.mode === 'registration')) {
      failure = new MiniAppError(flow.mode === 'registration' ? LineErrorCode.REGISTRATION_INCOMPLETE : LineErrorCode.LOGIN_REQUIRED, 'LINE login required');
    } else if (flow && (flow.closing || flow.mode === 'switching' || context !== ownerContext ||
      (registration && (flow.mode !== 'registration' || !flow.session)))) {
      failure = new MiniAppError(LineErrorCode.LOGIN_IN_PROGRESS, 'LINE login is already in progress');
    }
    const fresh: boolean = !flow;
    if (!flow && !failure) {
      try {
        flow = new LineLoginFlow(LineAccountUiLease.acquire(this.account), presenter, registration);
        this.flow = flow;
      } catch (error) { failure = MiniAppError.from(error as Object, LineErrorCode.LOGIN_IN_PROGRESS, 'LINE account is in use'); }
    }
    if (failure || !flow) {
      waiter.reject(failure ?? new MiniAppError(LineErrorCode.LOGIN_FAILED, 'LINE login failed'));
      return { result: waiter.result, cancel: (): void => {} };
    }
    const owned = flow;
    owned.waiters.add(waiter);
    if (fresh) {
      if (registration) { this.showRegistration(owned, registration); } else { this.run(owned); }
    }
    return { result: waiter.result, cancel: (): void => {
      if (!owned.waiters.delete(waiter)) { return; }
      const error = new MiniAppError(LineErrorCode.LOGIN_CANCELLED, 'LINE login cancelled');
      waiter.reject(error);
      if (owned.waiters.size === 0) { this.finish(owned, error); }
    } };
  }

  private current(flow: LineLoginFlow, generation?: number): boolean {
    return this.flow === flow && !flow.closing && (generation === undefined || generation === flow.generation);
  }

  private async run(flow: LineLoginFlow): Promise<void> {
    try {
      let restored: boolean = false;
      let failure: MiniAppError | undefined;
      try { restored = await this.account.restoreSession(); }
      catch (error) { failure = MiniAppError.from(error as Object, LineErrorCode.ACCOUNT_RESTORE_FAILED, 'LINE account restore failed'); }
      if (!this.current(flow)) { return; }
      if (restored) { await this.finish(flow); return; }
      if (failure?.code === LineErrorCode.LOGIN_IN_PROGRESS) { await this.finish(flow, failure); return; }
      flow.waiters.forEach((waiter: LineLoginWaiter): void => {
        if (waiter.reuseOnly) {
          flow.waiters.delete(waiter);
          waiter.reject(failure ?? new MiniAppError(LineErrorCode.LOGIN_REQUIRED, 'LINE login required'));
        }
      });
      if (!flow.waiters.size) { await this.finish(flow); return; }
      if (failure?.code === LineErrorCode.REGISTRATION_INCOMPLETE) {
        const presenter = flow.presenter?.registrationPresenter?.();
        if (!presenter) { await this.finish(flow, failure); return; }
        await this.showRegistration(flow, presenter);
      } else { await this.showLogin(flow, failure); }
    } catch (error) { if (this.current(flow)) { await this.finish(flow, MiniAppError.from(error as Object, LineErrorCode.LOGIN_FAILED, 'LINE login failed')); } }
  }

  private async showLogin(flow: LineLoginFlow, failure?: MiniAppError): Promise<void> {
    const presenter = flow.presenter;
    if (!presenter || !this.current(flow)) { return; }
    flow.mode = 'login';
    const generation = ++flow.generation;
    const controller = new LineLoginController(this.account, (state: LineLoginState): void => {
      if (this.current(flow, generation)) { presenter.update(state); }
    }, (): void => {
      const registration = presenter.registrationPresenter?.();
      if (registration && this.current(flow, generation)) { this.switchToRegistration(flow, registration); }
    });
    flow.controller = controller;
    flow.presentation = presenter;
    try {
      flow.showing = presenter.show(controller);
      await flow.showing;
      if (!this.current(flow, generation)) { return; }
      await controller.start(failure);
      if (this.current(flow, generation)) { await this.finish(flow); }
    } catch (error) {
      if (this.current(flow, generation)) { await this.finish(flow, MiniAppError.from(error as Object, LineErrorCode.LOGIN_FAILED, 'LINE login failed')); }
    }
  }

  private async switchToRegistration(flow: LineLoginFlow, presenter: LineRegistrationPresenter): Promise<void> {
    const old = flow.controller;
    flow.controller = undefined;
    const generation = ++flow.generation; // Invalidate BEFORE cancel can settle the old result.
    flow.mode = 'switching';
    old?.dispose();
    try {
      await flow.showing;
      await flow.presentation?.hide();
      if (this.current(flow, generation)) { await this.showRegistration(flow, presenter); }
    } catch (error) { if (this.current(flow, generation)) { await this.finish(flow, MiniAppError.from(error as Object, LineErrorCode.LOGIN_UI_FAILED, 'LINE dialog failed')); } }
  }

  private async showRegistration(flow: LineLoginFlow, presenter: LineRegistrationPresenter): Promise<void> {
    flow.mode = 'registration';
    const generation = ++flow.generation;
    try {
      presenter.assertCanPresent?.();
      const session = this.account.startOwnedPhoneRegistration((state: LinePhoneRegistrationState): void => {
        if (this.current(flow, generation)) { presenter.update(state); }
      }, flow.owner);
      flow.session = session;
      // Attach immediately: cancellation while mounting must not create an unhandled rejection.
      session.result.catch((): void => {});
      flow.presentation = presenter;
      flow.showing = presenter.show(session, (): void => { this.backFromRegistration(flow, generation); });
      await flow.showing;
      if (!this.current(flow, generation)) { return; }
      await session.result;
      if (this.current(flow, generation)) { await this.finish(flow); }
    } catch (error) {
      if (this.current(flow, generation)) { await this.finish(flow, MiniAppError.from(error as Object, LineErrorCode.REGISTRATION_FAILED, 'LINE registration failed')); }
    }
  }

  private async backFromRegistration(flow: LineLoginFlow, generation: number): Promise<void> {
    if (!this.current(flow, generation)) { return; }
    const stage = flow.session?.getState().stage;
    // Once creation may have started, back only closes. The manager retains any server lock.
    if (stage === 'creating' || stage === 'creationUncertain' || stage === 'finalizing' || stage === 'privacySettings' || stage === 'ageVerification' || stage === 'agreementRequired') {
      await this.finish(flow, new MiniAppError(LineErrorCode.REGISTRATION_CANCELLED, 'LINE registration closed'));
      return;
    }
    // Close admission before rejecting waiters or cancelling the old session.
    // Cleanup can await a dialog animation, but new registration waiters cannot join it.
    flow.mode = 'switching';
    flow.waiters.forEach((waiter: LineLoginWaiter): void => {
      if (waiter.registration) { flow.waiters.delete(waiter); waiter.reject(new MiniAppError(LineErrorCode.REGISTRATION_CANCELLED, 'LINE registration cancelled')); }
    });
    if (!flow.waiters.size || !flow.presenter) { await this.finish(flow, new MiniAppError(LineErrorCode.REGISTRATION_CANCELLED, 'LINE registration cancelled')); return; }
    const session = flow.session;
    flow.session = undefined;
    const next = ++flow.generation;
    session?.cancel();
    try {
      await flow.showing;
      await flow.presentation?.hide();
      if (this.current(flow, next)) { await this.showLogin(flow); }
    } catch (error) { if (this.current(flow, next)) { await this.finish(flow, MiniAppError.from(error as Object, LineErrorCode.LOGIN_UI_FAILED, 'LINE dialog failed')); } }
  }

  private async finish(flow: LineLoginFlow, failure?: MiniAppError): Promise<void> {
    if (!this.current(flow)) { return; }
    const accountVersion = this.account.getVersion();
    flow.closing = true;
    flow.generation++;
    const controller = flow.controller;
    const session = flow.session;
    flow.controller = undefined;
    flow.session = undefined;
    controller?.dispose();
    session?.cancel();
    try { await flow.showing; } catch (_) { /* Clean partially mounted UI. */ }
    try { await flow.presentation?.hide(); }
    catch (error) { failure = failure ?? MiniAppError.from(error as Object, LineErrorCode.LOGIN_UI_FAILED, 'LINE dialog failed'); }
    if (!failure && accountVersion !== this.account.getVersion()) { failure = new MiniAppError(LineErrorCode.LOGIN_CANCELLED, 'LINE account changed'); }
    LineAccountUiLease.release(this.account, flow.owner);
    if (this.flow === flow) { this.flow = undefined; }
    flow.waiters.forEach((waiter: LineLoginWaiter): void => { if (failure) { waiter.reject(failure); } else { waiter.resolve(); } });
    flow.waiters.clear();
  }
}
