import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';
import { BridgeContext } from '../../../core/Runtime';
import { UserInfoRequest, UserInfoResult, VkAdapter } from '../VkAdapter';
import { ParamAssert } from '../../../utils/ParamAssert';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';
import { MiniAppError } from '../../../core/MiniAppError';
import { APP_IN_BACKGROUND, NOT_SUPPORTED } from '../../../core/MiniAppErrorCode';
import { ContactPickerTools } from '../../../capabilities/contacts/ContactPickerTools';

export const VK_WEB_APP_OPEN_CONTACTS: string = 'VKWebAppOpenContacts';

export interface VkOpenContactsResult {
  phone?: string;
  first_name?: string;
  last_name?: string;
}

export const VK_WEB_APP_GET_USER_INFO: string = 'VKWebAppGetUserInfo';

export interface VkUserInfoParams {
  user_id?: number;
  user_ids?: string;
}

export interface VkUserInfoLocation {
  id: number;
  title: string;
}

export interface VkUserInfoResult {
  id: number;
  first_name: string;
  last_name: string;
  sex: number;
  city: VkUserInfoLocation;
  country: VkUserInfoLocation;
  bdate?: string;
  bdate_visibility: number;
  can_access_closed: boolean;
  is_closed: boolean;
  photo_100: string;
  photo_200: string;
  photo_max_orig?: string;
  timezone?: number;
}

/** 将 VK 用户资料和设备联系人请求转换为官方字段格式。 */
export class VkUsersHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private readonly adapter: VkAdapter;
  private picker?: ContactPickerTools;
  private disposed: boolean = false;

  constructor(context: BridgeContext, adapter: VkAdapter) {
    this.adapter = adapter;
    this.context = context;
  }

  @VkEvent({ name: VK_WEB_APP_OPEN_CONTACTS, timeout: -1 })
  async openContacts(params: object): Promise<VkOpenContactsResult> {
    this.assertOpen();
    ParamAssert.assertObject(params, 'params');
    try {
      const documentId = this.context.getDocumentId();
      const selected = await this.getPicker().pick();
      this.assertOpen();
      if (documentId !== this.context.getDocumentId()) {
        throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
      }
      const name = selected.name;
      const givenName = name?.givenName ?? '';
      const familyName = name?.familyName ?? '';
      const firstName = givenName.length === 0 && familyName.length === 0 ? (name?.fullName ?? '') : givenName;
      const result: VkOpenContactsResult = {
        phone: selected.phoneNumbers![0].phoneNumber,
        first_name: firstName,
        last_name: familyName
      };
      return result;
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      if (error instanceof MiniAppError) {
        switch (error.code) {
          case APP_IN_BACKGROUND:
            throw VkBridgeError.client(VkClientErrorCode.BACKGROUND, undefined, error);
          // 对齐客户端效果，和文档不一致
          // case USER_CANCELLED:
          //   throw VkBridgeError.client(VkClientErrorCode.USER_DENIED, undefined, error);
          case NOT_SUPPORTED:
            throw VkBridgeError.client(VkClientErrorCode.UNSUPPORTED_PLATFORM, undefined, error);
        }
      }
      // 对齐客户端效果，和文档不一致
      // throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
      const result: VkOpenContactsResult = {}
      return result
    }
  }

  // @VkEvent({ name: VK_WEB_APP_GET_USER_INFO })
  async getUserInfo(params: VkUserInfoParams): Promise<VkUserInfoResult> {
    this.assertOpen();
    ParamAssert.assertObject(params, 'params');
    ParamAssert.assertOptionalNumber(params.user_id, 'user_id');
    ParamAssert.assertOptionalString(params.user_ids, 'user_ids');
    try {
      if (params.user_id !== undefined &&
        (!Number.isSafeInteger(params.user_id) || params.user_id <= 0)) {
        throw VkBridgeError.client(VkClientErrorCode.INVALID_PARAMS);
      }
      const request: UserInfoRequest = {
        userId: params.user_id,
        userIds: params.user_ids
      };
      const profile: UserInfoResult = await this.adapter.requestUserInfo(request);
      this.assertOpen();
      const result: VkUserInfoResult = {
        id: profile.id,
        first_name: profile.firstName,
        last_name: profile.lastName,
        sex: profile.sex,
        city: { id: profile.city.id, title: profile.city.title },
        country: { id: profile.country.id, title: profile.country.title },
        bdate_visibility: profile.birthDateVisibility,
        can_access_closed: profile.canAccessClosed,
        is_closed: profile.isClosed,
        photo_100: profile.photo100,
        photo_200: profile.photo200
      };
      if (profile.birthDate !== undefined) {
        result.bdate = profile.birthDate;
      }
      if (profile.photoMaxOriginal !== undefined) {
        result.photo_max_orig = profile.photoMaxOriginal;
      }
      if (profile.timezone !== undefined) {
        result.timezone = profile.timezone;
      }
      return result;
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    const picker = this.picker;
    this.picker = undefined;
    picker?.dispose();
  }

  private getPicker(): ContactPickerTools {
    if (!this.picker) {
      const picker = new ContactPickerTools(this.context.uiAbilityContext);
      this.picker = picker;
      this.context.addCleanup((): void => {
        if (this.picker === picker) {
          this.picker = undefined;
          picker.dispose();
        }
      });
    }
    return this.picker;
  }

  private assertOpen(): void {
    if (this.disposed) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
    }
  }
}
