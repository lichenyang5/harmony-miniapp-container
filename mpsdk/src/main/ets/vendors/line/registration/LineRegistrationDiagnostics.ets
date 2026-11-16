import { MiniAppError } from '../../../core/MiniAppError';
import { SdkLogger } from '../../../logging/SdkLogger';

export interface LineRegistrationDiagnosticOperation {
  kind: 'action' | 'rpc';
  capability: string;
  requestId: string;
  startedAt: number;
}

/** Local correlation only: never use authSessionId or account/device identifiers. */
export class LineRegistrationDiagnostics {
  private static sequence: number = 0;
  private readonly sessionId: string = `line-registration-${++LineRegistrationDiagnostics.sequence}`;
  private sequence: number = 0;
  private readonly now: () => number;

  constructor(now: () => number = (): number => Date.now()) { this.now = now; }

  start(kind: 'action' | 'rpc', capability: string): LineRegistrationDiagnosticOperation {
    const operation: LineRegistrationDiagnosticOperation = {
      kind, capability, requestId: `${this.sessionId}-${++this.sequence}`, startedAt: this.now()
    };
    SdkLogger.info('LineRegistration', `${kind}Started`, {
      sessionId: this.sessionId, requestId: operation.requestId, capability
    });
    return operation;
  }

  complete(operation: LineRegistrationDiagnosticOperation): void {
    SdkLogger.info('LineRegistration', `${operation.kind}Completed`, {
      sessionId: this.sessionId, requestId: operation.requestId, capability: operation.capability,
      durationMs: Math.max(0, this.now() - operation.startedAt)
    });
  }

  fail(operation: LineRegistrationDiagnosticOperation, error: MiniAppError): void {
    SdkLogger.warn('LineRegistration', `${operation.kind}Failed`, {
      sessionId: this.sessionId, requestId: operation.requestId, capability: operation.capability,
      code: error.code, durationMs: Math.max(0, this.now() - operation.startedAt)
    });
  }

  event(event: string, stage: string, code?: string): void {
    SdkLogger.info('LineRegistration', event, { sessionId: this.sessionId, capability: stage, code });
  }
}
