import { LineErrorCode } from '../LineErrorCode';
import { MiniAppError } from '../../../core/MiniAppError';
import { LineRegistrationFailure, LineRegistrationWebAuthDetails } from './LineRegistrationTypes';

export function lineRegistrationInvalid(): MiniAppError {
  return new MiniAppError(LineErrorCode.REGISTRATION_PROTOCOL_ERROR, 'Invalid LINE registration response');
}

/** Raw server text is deliberately excluded; challenge credentials stay native. */
export class LineRegistrationError extends MiniAppError {
  readonly wireCode?: number;
  readonly webAuthDetails?: LineRegistrationWebAuthDetails;
  readonly service: 'registration' | 'talk';

  constructor(failure: LineRegistrationFailure, service: 'registration' | 'talk' = 'registration') {
    let code: string = LineErrorCode.REGISTRATION_REJECTED;
    if (service === 'talk') {
      code = failure.code === 119 ? LineErrorCode.REGISTRATION_TOKEN_REFRESH_REQUIRED : LineErrorCode.REGISTRATION_TALK_REJECTED;
    } else {
      switch (failure.code) {
        case 0: code = LineErrorCode.REGISTRATION_INTERNAL_ERROR; break;
        case 1: code = LineErrorCode.REGISTRATION_ILLEGAL_ARGUMENT; break;
        case 2: code = LineErrorCode.REGISTRATION_VERIFICATION_FAILED; break;
        case 3: code = LineErrorCode.REGISTRATION_NOT_FOUND; break;
        case 4: code = LineErrorCode.REGISTRATION_RETRY_LATER; break;
        case 5: code = LineErrorCode.REGISTRATION_HUMAN_VERIFICATION_REQUIRED; break;
        case 100: code = LineErrorCode.REGISTRATION_INVALID_CONTEXT; break;
        case 101: code = LineErrorCode.REGISTRATION_APP_UPGRADE_REQUIRED; break;
      }
    }
    super(code, 'LINE registration request was rejected');
    this.wireCode = failure.code;
    this.webAuthDetails = failure.webAuthDetails;
    this.service = service;
  }
}
