import { LineErrorCode } from '../LineErrorCode';
import { LineRegistrationTalkRpcMethod } from '../network/LineRpcConstants';
import { LineCompactWriter } from '../network/LineCompactCodec';
import { LineCompactType } from '../network/LineRpcConstants';
import { MiniAppError } from '../../../core/MiniAppError';
import { LineRegistrationCodec } from './LineRegistrationCodec';
import { LineCountryAgreement, LineRegistrationConfigurationsRequest,
  LineRegistrationPrivacy } from './LineRegistrationTypes';

/** NORMAL Talk (/S4), distinct from the pre-authentication REGISTRATION Talk route. */
export class LineRegistrationTalkCodec {
  static initialization(method: string, sequence: number): Uint8Array {
    return LineRegistrationCodec.request(method, sequence, (writer: LineCompactWriter): void => {
      writer.field(1, LineCompactType.I32);
      writer.integer(2); // gp8.oh.INITIALIZATION, not the local REGISTRATION ordinal.
    }, false);
  }

  static updateName(displayName: string, reqSeq: number, sequence: number): Uint8Array {
    return LineRegistrationCodec.request(LineRegistrationTalkRpcMethod.UPDATE_NAME, sequence, (writer: LineCompactWriter): void => {
      writer.field(1, LineCompactType.I32);
      writer.integer(reqSeq);
      writer.field(2, LineCompactType.STRUCT, 1);
      writer.field(1, LineCompactType.MAP);
      writer.uint(1);
      writer.byte(0x5c); // map<enum, ProfileContent>
      writer.integer(2); // DISPLAY_NAME
      LineRegistrationCodec.text(writer, 1, displayName);
      writer.byte(LineCompactType.STOP); // ProfileContent, with meta absent.
      writer.byte(LineCompactType.STOP); // UpdateProfileAttributesRequest
    }, false);
  }

  static configurations(request: LineRegistrationConfigurationsRequest, sequence: number): Uint8Array {
    return LineRegistrationCodec.request(LineRegistrationTalkRpcMethod.CONFIGURATIONS, sequence, (writer: LineCompactWriter): void => {
      writer.field(2, LineCompactType.I64);
      writer.long(request.revision);
      LineRegistrationCodec.text(writer, 3, request.regionOfUsim, 2);
      LineRegistrationCodec.text(writer, 4, request.regionOfTelephone, 3);
      LineRegistrationCodec.text(writer, 5, request.regionOfLocale, 4);
      LineRegistrationCodec.text(writer, 6, request.carrier, 5);
      writer.field(7, LineCompactType.I32, 6);
      writer.integer(2);
    }, false);
  }

  private static settings(sequence: number, reqSeq: number, attributes: number[],
    write: (writer: LineCompactWriter) => void): Uint8Array {
    return LineRegistrationCodec.request(LineRegistrationTalkRpcMethod.UPDATE_SETTINGS, sequence, (writer: LineCompactWriter): void => {
      writer.field(1, LineCompactType.I32);
      writer.integer(reqSeq);
      writer.field(4, LineCompactType.SET, 1);
      writer.byte((attributes.length << 4) | LineCompactType.I32);
      attributes.forEach((attribute: number): void => { writer.integer(attribute); });
      writer.field(3, LineCompactType.STRUCT, 4);
      write(writer);
      writer.byte(LineCompactType.STOP);
    }, false);
  }

  static privacy(request: LineRegistrationPrivacy, reqSeq: number, sequence: number): Uint8Array {
    const attributes: number[] = [6, 7];
    if (request.privacySearchByUserid !== undefined) { attributes.push(13); }
    return LineRegistrationTalkCodec.settings(sequence, reqSeq, attributes, (writer: LineCompactWriter): void => {
      writer.field(20, request.privacySyncContacts ? LineCompactType.BOOLEAN_TRUE : LineCompactType.BOOLEAN_FALSE);
      writer.field(21, request.privacySearchByPhoneNumber ? LineCompactType.BOOLEAN_TRUE :
        LineCompactType.BOOLEAN_FALSE, 20);
      if (request.privacySearchByUserid !== undefined) {
        writer.field(22, request.privacySearchByUserid ? LineCompactType.BOOLEAN_TRUE :
          LineCompactType.BOOLEAN_FALSE, 21);
      }
    });
  }

  static countryAgreement(policy: LineCountryAgreement, timestampMs: number,
    reqSeq: number, sequence: number): Uint8Array {
    if (!Number.isSafeInteger(timestampMs) || timestampMs === 0) {
      throw new MiniAppError(LineErrorCode.REGISTRATION_ILLEGAL_ARGUMENT, 'Invalid LINE agreement timestamp');
    }
    let attribute: number;
    let field: number;
    switch (policy) {
      case LineCountryAgreement.GDPR: attribute = 53; field = 80; break;
      case LineCountryAgreement.ICNA: attribute = 66; field = 94; break;
      case LineCountryAgreement.TH_PDPA: attribute = 76; field = 105; break;
      case LineCountryAgreement.ID_PDP: attribute = 92; field = 122; break;
      default:
        throw new MiniAppError(LineErrorCode.REGISTRATION_ILLEGAL_ARGUMENT, 'Unsupported LINE country agreement');
    }
    // Preserve caller-selected acceptance (+) or refusal (-); never decide consent here.
    return LineRegistrationTalkCodec.settings(sequence, reqSeq, [attribute], (writer: LineCompactWriter): void => {
      writer.field(field, LineCompactType.I64);
      writer.long(timestampMs);
    });
  }
}
