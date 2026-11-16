import { describe, expect, it } from '@ohos/hypium';
import { BridgeContext } from '../main/ets/core/Runtime';
import { MiniAppError } from '../main/ets/core/MiniAppError';
import { CAPABILITY_ALREADY_REGISTERED_OR_INVALID } from '../main/ets/core/MiniAppErrorCode';
import { BaseVkEventHandler } from '../main/ets/vendors/vk/events/BaseVkEventHandler';
import { VkEvent } from '../main/ets/vendors/vk/events/VkEvent';
import { VkResponse } from '../main/ets/vendors/vk/events/VkResponse';
import { VkEventRegistry } from '../main/ets/vendors/vk/events/VkEventRegistry';
import { InterceptResult } from '../main/ets/vendors/vk/InterceptResult';
import { VkBridgeEvent, VkBridgeProtocol } from '../main/ets/vendors/vk/VkBridgeProtocol';
import { VkBridgeProxy } from '../main/ets/vendors/vk/VkBridgeProxy';
import { VkResponseInterceptor } from '../main/ets/vendors/vk/interceptors/VkResponseInterceptor';
import { EmptyParams, VkTestContext, VkTestSession } from './TestContext';

interface TestData {
  value: string;
}

// 对照用户提供的 Android 单个开放社区结果；额外 Web 字段不得进入 group。
const OPEN_WEB_GROUP_EVENT: string = '{"type":"VKWebAppGetGroupInfoResult","data":{' +
  '"id":241534146,"description":"","members_count":2,"name":"社区名称",' +
  '"screen_name":"club241534146","is_closed":0,"type":"group",' +
  '"is_admin":0,"is_member":0,"is_advertiser":0,' +
  '"photo_50":"https://example.com/50.jpg","photo_100":"https://example.com/100.jpg",' +
  '"photo_200":"https://example.com/200.jpg","photo_base":"https://example.com/base.jpg",' +
  '"request_id":"group-request"},"trace":9}';

const OPEN_ANDROID_GROUP_EVENT: string = '{"type":"VKWebAppGetGroupInfoResult","data":{"group":{' +
  '"description":"","id":241534146,"is_closed":"OPEN","members_count":2,"name":"社区名称",' +
  '"photo_100":"https://example.com/100.jpg","photo_200":"https://example.com/200.jpg",' +
  '"photo_50":"https://example.com/50.jpg","screen_name":"club241534146","type":"group"},' +
  '"request_id":"group-request"},"trace":9}';

class MixedHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  disposed: number = 0;
  lastResult?: InterceptResult;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  @VkEvent({ name: 'Shared' })
  async request(params: TestData): Promise<TestData> {
    return params;
  }

  @VkResponse('Shared')
  response(event: VkBridgeEvent<TestData>): InterceptResult {
    event.data.value = this.context.appId;
    this.lastResult = InterceptResult.hook(event);
    return this.lastResult;
  }

  @VkResponse('Pass')
  pass(event: VkBridgeEvent<TestData>): InterceptResult {
    event.data.value = 'must-not-leak';
    return InterceptResult.pass();
  }

  @VkResponse('Block')
  block(_event: VkBridgeEvent): InterceptResult {
    return InterceptResult.intercept();
  }

  @VkResponse('Fail')
  fail(event: VkBridgeEvent<TestData>): InterceptResult {
    event.data.value = 'must-not-leak';
    throw new Error('response test failure');
  }

  @VkResponse('EmptyHook')
  emptyHook(_event: VkBridgeEvent): InterceptResult {
    return InterceptResult.hook();
  }

  dispose(): void {
    this.disposed++;
  }
}

class ConflictingHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  disposed: number = 0;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  @VkEvent({ name: 'NewRequest' })
  async request(params: object): Promise<object> {
    return params;
  }

  @VkResponse('Shared')
  response(_event: VkBridgeEvent): InterceptResult {
    return InterceptResult.pass();
  }

  dispose(): void {
    this.disposed++;
  }
}

class TimeoutHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  @VkEvent({ name: 'DefaultTimeout' })
  defaultTimeout(_event: VkBridgeEvent): Promise<EmptyParams> {
    return Promise.resolve(new EmptyParams());
  }

  @VkEvent({ name: 'NoTimeout', timeout: 0 })
  noTimeout(_event: VkBridgeEvent): Promise<EmptyParams> {
    return Promise.resolve(new EmptyParams());
  }

  @VkEvent({ name: 'NegativeTimeout', timeout: -1 })
  negativeTimeout(_event: VkBridgeEvent): Promise<EmptyParams> {
    return Promise.resolve(new EmptyParams());
  }

  dispose(): void {
  }
}

class FractionalTimeoutHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  @VkEvent({ name: 'FractionalTimeout', timeout: 1.5 })
  request(_event: VkBridgeEvent): Promise<EmptyParams> {
    return Promise.resolve(new EmptyParams());
  }

  dispose(): void {
  }
}

class NanTimeoutHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  @VkEvent({ name: 'NanTimeout', timeout: Number.NaN })
  request(_event: VkBridgeEvent): Promise<EmptyParams> {
    return Promise.resolve(new EmptyParams());
  }

  dispose(): void {
  }
}

class PositiveInfinityTimeoutHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  @VkEvent({ name: 'PositiveInfinityTimeout', timeout: Number.POSITIVE_INFINITY })
  request(_event: VkBridgeEvent): Promise<EmptyParams> {
    return Promise.resolve(new EmptyParams());
  }

  dispose(): void {
  }
}

class NegativeInfinityTimeoutHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  @VkEvent({ name: 'NegativeInfinityTimeout', timeout: Number.NEGATIVE_INFINITY })
  request(_event: VkBridgeEvent): Promise<EmptyParams> {
    return Promise.resolve(new EmptyParams());
  }

  dispose(): void {
  }
}

export default function vkResponseTest(): void {
  describe('VkResponse', () => {
    it('alignsOpenGroupInfoWithAndroidThroughTheExistingResponseEntry', 0, () => {
      const context = new VkTestSession();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new VkResponseInterceptor(context, registry)]);
      const proxy = new VkBridgeProxy(context, registry);
      try {
        const result = proxy.onInterceptResponse(OPEN_WEB_GROUP_EVENT);
        expect(result.intercept).assertFalse();
        expect(JSON.stringify(result.data)).assertEqual(OPEN_ANDROID_GROUP_EVENT);
        expect(registry.getHandler('VKWebAppGetGroupInfo') === undefined).assertTrue();
        expect(proxy.onInterceptRequest(
          '{"type":"vk-connect","handler":"VKWebAppGetGroupInfo",' +
            '"params":{"group_id":241534146,"request_id":"group-request"}}', 'group-route').intercept)
          .assertFalse();
      } finally {
        registry.dispose();
        context.close();
      }
    });

    it('preservesGroupInfoRequestIdsAndDoesNotInventAnOmittedId', 0, () => {
      const context = new VkTestSession();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new VkResponseInterceptor(context, registry)]);
      const proxy = new VkBridgeProxy(context, registry);
      try {
        const ids: string[] = ['0', '42', '""', '"another-request"'];
        ids.forEach((id: string): void => {
          const input = OPEN_WEB_GROUP_EVENT.replace('"group-request"', id);
          const expected = OPEN_ANDROID_GROUP_EVENT.replace('"group-request"', id);
          expect(JSON.stringify(proxy.onInterceptResponse(input).data)).assertEqual(expected);
        });
        const withoutId = OPEN_WEB_GROUP_EVENT.replace(',"request_id":"group-request"', '');
        const expectedWithoutId = OPEN_ANDROID_GROUP_EVENT.replace(',"request_id":"group-request"', '');
        expect(JSON.stringify(proxy.onInterceptResponse(withoutId).data)).assertEqual(expectedWithoutId);
      } finally {
        registry.dispose();
        context.close();
      }
    });

    it('alignsAllDocumentedGroupStatesAndAllowsPrivateFieldsToBeOmitted', 0, () => {
      const context = new VkTestSession();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new VkResponseInterceptor(context, registry)]);
      const proxy = new VkBridgeProxy(context, registry);
      try {
        const states: string[] = ['OPEN', 'CLOSED', 'PRIVATE'];
        states.forEach((state: string, index: number): void => {
          const input = OPEN_WEB_GROUP_EVENT.replace('"is_closed":0', '"is_closed":' + index);
          const expected = OPEN_ANDROID_GROUP_EVENT.replace('"OPEN"', '"' + state + '"');
          expect(JSON.stringify(proxy.onInterceptResponse(input).data)).assertEqual(expected);
        });
        const privateInput = OPEN_WEB_GROUP_EVENT.replace('"is_closed":0', '"is_closed":2')
          .replace('"description":"",', '').replace('"members_count":2,', '').replace('"is_member":0,', '');
        const privateExpected = OPEN_ANDROID_GROUP_EVENT.replace('"OPEN"', '"PRIVATE"')
          .replace('"description":"",', '').replace('"members_count":2,', '');
        expect(JSON.stringify(proxy.onInterceptResponse(privateInput).data)).assertEqual(privateExpected);
      } finally {
        registry.dispose();
        context.close();
      }
    });

    it('passesWrappedMultipleAndUnverifiedGroupInfoResultsUnchanged', 0, () => {
      const context = new VkTestSession();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new VkResponseInterceptor(context, registry)]);
      const proxy = new VkBridgeProxy(context, registry);
      try {
        const inputs: string[] = [OPEN_ANDROID_GROUP_EVENT,
          '{"type":"VKWebAppGetGroupInfoResult","data":{"result":[],"request_id":"many"}}',
          OPEN_WEB_GROUP_EVENT.replace('"is_closed":0', '"is_closed":3'),
          OPEN_WEB_GROUP_EVENT.replace('"is_closed":0', '"is_closed":-1'),
          OPEN_WEB_GROUP_EVENT.replace('"is_closed":0', '"is_closed":0.5'),
          OPEN_WEB_GROUP_EVENT.replace('"is_closed":0', '"is_closed":"0"'),
          OPEN_WEB_GROUP_EVENT.replace('"is_closed":0', '"is_closed":null'),
          OPEN_WEB_GROUP_EVENT.replace('"data":{', '"data":{"group":{},'),
          OPEN_WEB_GROUP_EVENT.replace('"data":{', '"data":{"result":[],')];
        inputs.forEach((input: string): void => {
          const result = proxy.onInterceptResponse(input);
          expect(result.intercept).assertFalse();
          expect(result.data === undefined).assertTrue();
        });
      } finally {
        registry.dispose();
        context.close();
      }
    });

    it('passesMalformedGroupInfoFailuresAndOtherMethodsWithoutPartialConversion', 0, () => {
      const context = new VkTestSession();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new VkResponseInterceptor(context, registry)]);
      const proxy = new VkBridgeProxy(context, registry);
      try {
        const inputs: string[] = [
          OPEN_WEB_GROUP_EVENT.replace('"id":241534146,', ''),
          OPEN_WEB_GROUP_EVENT.replace('"id":241534146', '"id":"241534146"'),
          OPEN_WEB_GROUP_EVENT.replace('"name":"社区名称"', '"name":null'),
          OPEN_WEB_GROUP_EVENT.replace('"members_count":2', '"members_count":"2"'),
          OPEN_WEB_GROUP_EVENT.replace('"members_count":2', '"members_count":1e400'),
          OPEN_WEB_GROUP_EVENT.replace('"description":"",', ''),
          OPEN_WEB_GROUP_EVENT.replace('"members_count":2,', ''),
          OPEN_WEB_GROUP_EVENT.replace('"is_closed":0', '"is_closed":2')
            .replace('"description":""', '"description":null'),
          OPEN_WEB_GROUP_EVENT.replace('"is_closed":0', '"is_closed":2')
            .replace('"members_count":2', '"members_count":null'),
          OPEN_WEB_GROUP_EVENT.replace('"photo_200":"https://example.com/200.jpg",', ''),
          OPEN_WEB_GROUP_EVENT.replace('VKWebAppGetGroupInfoResult', 'VKWebAppGetUserInfoResult'),
          '{"type":"VKWebAppGetGroupInfoFailed","data":{"error_type":"client_error",' +
            '"error_data":{"error_code":11,"error_reason":"Access denied"},"request_id":"failed"}}'];
        inputs.forEach((input: string): void => {
          const result = proxy.onInterceptResponse(input);
          expect(result.intercept).assertFalse();
          expect(result.data === undefined).assertTrue();
        });
      } finally {
        registry.dispose();
        context.close();
      }
    });

    it('parsesNotificationsAndRejectsMalformedEnvelopes', 0, () => {
      const json = '{"type":"VKWebAppUpdateConfig","data":{"scheme":"bright_light","app_id":7879029}}';
      expect(JSON.stringify(VkBridgeProtocol.parseResponse(json))).assertEqual(json);
      const invalid: string[] = ['broken', 'null', '[]', '{}', '{"type":1,"data":{}}',
        '{"type":" ","data":{}}', '{"type":"X"}', '{"type":"X","data":null}',
        '{"type":"X","data":[]}', '{"type":"X","data":1}'];
      invalid.forEach((value: string): void => {
        expect(VkBridgeProtocol.parseResponse(value) === undefined).assertTrue();
      });
    });

    it('registersBothDecoratorsAndBindsThisWithoutAdvertisingResponses', 0, () => {
      const context = new VkTestSession();
      const registry = new VkEventRegistry(context);
      const handler = new MixedHandler(context);
      registry.initHandler([handler, handler]);
      registry.initHandler([handler]);
      expect(registry.getSupportedHandlers().join(',')).assertEqual('Shared');
      const proxy = new VkBridgeProxy(context, registry);
      const result = proxy.onInterceptResponse('{"type":"Shared","data":{"value":"old","extra":7},"trace":9}');
      expect(result === handler.lastResult).assertTrue();
      expect(JSON.stringify(result.data)).assertEqual(
        '{"type":"Shared","data":{"value":"vk-handler-test-app","extra":7},"trace":9}');
      registry.dispose();
      registry.dispose();
      expect(handler.disposed).assertEqual(1);
      expect(registry.getResponseInterceptor('Shared') === undefined).assertTrue();
      expect(registry.getHandler('Shared') === undefined).assertTrue();
      context.close();
    });

    it('passesUnknownInvalidFailedAndUnmodifiedResponsesAndSupportsBlocking', 0, () => {
      const context = new VkTestSession();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new MixedHandler(context)]);
      const proxy = new VkBridgeProxy(context, registry);
      const inputs: string[] = ['invalid', '{"type":"Shared","data":null}',
        '{"type":"Unknown","data":{}}', '{"type":"Pass","data":{"value":"old"}}',
        '{"type":"Fail","data":{"value":"old"}}', '{"type":"EmptyHook","data":{}}'];
      inputs.forEach((input: string): void => {
        const result = proxy.onInterceptResponse(input);
        expect(result.intercept).assertFalse();
        expect(result.data === undefined).assertTrue();
      });
      expect(proxy.onInterceptResponse('{"type":"Block","data":{}}').intercept).assertTrue();
      registry.dispose();
      context.close();
    });

    it('rejectsResponseConflictsWithoutPartiallyRegisteringRequests', 0, () => {
      const context = new VkTestContext();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new MixedHandler(context)]);
      const rejected = new ConflictingHandler(context);
      let failed: boolean = false;
      try {
        registry.initHandler([rejected]);
      } catch (_) {
        failed = true;
      }
      expect(failed).assertTrue();
      expect(registry.getHandler('NewRequest') === undefined).assertTrue();
      registry.dispose();
      expect(rejected.disposed).assertEqual(0);
    });

    it('rejectsSameBatchConflictsAndContextMismatchBeforeTakingOwnership', 0, () => {
      const context = new VkTestContext();
      const registry = new VkEventRegistry(context);
      let conflicts: number = 0;
      try {
        registry.initHandler([new MixedHandler(context), new ConflictingHandler(context)]);
      } catch (_) {
        conflicts++;
      }
      try {
        registry.initHandler([new MixedHandler(new VkTestContext())]);
      } catch (_) {
        conflicts++;
      }
      expect(conflicts).assertEqual(2);
      expect(registry.getSupportedHandlers().length).assertEqual(0);
      expect(registry.getResponseInterceptor('Shared') === undefined).assertTrue();
      registry.dispose();
    });

    it('normalizesEventTimeoutsAndRejectsInvalidValuesAtomically', 0, () => {
      const context = new VkTestContext();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new TimeoutHandler(context)]);
      expect(registry.getHandler('DefaultTimeout')?.timeout).assertEqual(30000);
      expect(registry.getHandler('NoTimeout')?.timeout).assertEqual(0);
      expect(registry.getHandler('NegativeTimeout')?.timeout).assertEqual(-1);

      const invalidHandlers: BaseVkEventHandler[] = [
        new FractionalTimeoutHandler(context),
        new NanTimeoutHandler(context),
        new PositiveInfinityTimeoutHandler(context),
        new NegativeInfinityTimeoutHandler(context)
      ];
      invalidHandlers.forEach((handler: BaseVkEventHandler): void => {
        let errorCode: string = '';
        try {
          registry.initHandler([handler]);
        } catch (error) {
          errorCode = (error as MiniAppError).code;
        }
        expect(errorCode).assertEqual(CAPABILITY_ALREADY_REGISTERED_OR_INVALID);
      });
      expect(registry.getHandler('FractionalTimeout') === undefined).assertTrue();
      expect(registry.getHandler('NanTimeout') === undefined).assertTrue();
      expect(registry.getHandler('PositiveInfinityTimeout') === undefined).assertTrue();
      expect(registry.getHandler('NegativeInfinityTimeout') === undefined).assertTrue();
      registry.dispose();
    });

    it('migratesOnlyExistingResponsesAndReadsCurrentSupportedHandlers', 0, () => {
      const context = new VkTestSession();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new VkResponseInterceptor(context, registry)]);
      const proxy = new VkBridgeProxy(context, registry);
      registry.initHandler([new MixedHandler(context)]);
      const merged = proxy.onInterceptResponse(
        '{"type":"SetSupportedHandlers","data":{"supportedHandlers":["Official","Shared"],"other":1}}');
      expect(JSON.stringify(merged.data)).assertEqual(
        '{"type":"SetSupportedHandlers","data":{"supportedHandlers":["VKWebAppInit","VKWebAppGetConfig","VKWebAppGetUserInfo","Shared","Official"],"other":1}}');
      const added = proxy.onInterceptResponse('{"type":"SetSupportedHandlers","data":{"supportedHandlers":[]}}');
      expect(JSON.stringify(added.data))
        .assertContain('"supportedHandlers":["VKWebAppInit","VKWebAppGetConfig","VKWebAppGetUserInfo","Shared"]');
      expect(proxy.onInterceptResponse('{"type":"VKWebAppUpdateConfig","data":{"vk_platform":"mobile_web"}}').data ===
        undefined).assertTrue();
      registry.dispose();
      context.close();
    });

    it('preservesOriginalLaunchParamsResponseWithoutReplacingSignedFields', 0, () => {
      const context = new VkTestSession();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new VkResponseInterceptor(context, registry)]);
      const proxy = new VkBridgeProxy(context, registry);
      try {
        const original = '{"type":"VKWebAppGetLaunchParamsResult","data":{' +
          '"vk_platform":"mobile_web","vk_language":"ru","vk_access_token_settings":"friends,groups",' +
          '"vk_app_id":54769936,"vk_user_id":7,"sign":"test-sign","request_id":"a",' +
          '"nested":{"keep":1}},"request_id":"a"}';
        const result = proxy.onInterceptResponse(original);
        expect(result.intercept).assertFalse();
        expect(JSON.stringify(result.data)).assertEqual(original);
      } finally {
        registry.dispose();
        context.close();
      }
    });

    it('doesNotAddMissingFieldsToLaunchParamsResponse', 0, () => {
      const context = new VkTestSession();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new VkResponseInterceptor(context, registry)]);
      const proxy = new VkBridgeProxy(context, registry);
      try {
        const originals: string[] = [
          '{"type":"VKWebAppGetLaunchParamsResult","data":{"sign":"test-sign","request_id":0}}',
          '{"type":"VKWebAppGetLaunchParamsResult","data":{}}'
        ];
        originals.forEach((original: string): void => {
          const result = proxy.onInterceptResponse(original);
          expect(result.intercept).assertFalse();
          expect(JSON.stringify(result.data)).assertEqual(original);
        });
      } finally {
        registry.dispose();
        context.close();
      }
    });

    it('passesMalformedSupportedListsInsteadOfThrowingOrReplacing', 0, () => {
      const context = new VkTestSession();
      const registry = new VkEventRegistry(context);
      registry.initHandler([new VkResponseInterceptor(context, registry)]);
      const proxy = new VkBridgeProxy(context, registry);
      const values: string[] = ['null', '3', '"text"', '{}', '["ok",2]'];
      values.forEach((value: string): void => {
        const result =
          proxy.onInterceptResponse('{"type":"SetSupportedHandlers","data":{"supportedHandlers":' + value + '}}');
        expect(result.data === undefined).assertTrue();
        expect(result.intercept).assertFalse();
      });
      registry.dispose();
      context.close();
    });

    it('keepsSameAppIdRegistriesIndependentUntilTheirOwnerDisposes', 0, () => {
      const context = new VkTestSession();
      const registry = new VkEventRegistry(context);
      const handler = new MixedHandler(context);
      registry.initHandler([handler]);
      const proxy = new VkBridgeProxy(context, registry);
      const replacementContext = new VkTestSession();
      const replacement = new VkEventRegistry(replacementContext);
      replacement.initHandler([new MixedHandler(replacementContext)]);
      expect(handler.disposed).assertEqual(0);
      expect(proxy.onInterceptResponse('{"type":"Shared","data":{"value":"old"}}').data !== undefined).assertTrue();
      const activeProxy = new VkBridgeProxy(replacementContext, replacement);
      registry.dispose();
      registry.dispose();
      expect(handler.disposed).assertEqual(1);
      expect(proxy.onInterceptResponse('{"type":"Shared","data":{"value":"old"}}').data === undefined).assertTrue();
      expect(replacement.isActiveFor(replacementContext)).assertTrue();
      expect(activeProxy.onInterceptResponse('{"type":"Shared","data":{"value":"old"}}').data !== undefined)
        .assertTrue();
      activeProxy.dispose();
      expect(activeProxy.onInterceptResponse('{"type":"Shared","data":{"value":"old"}}').data === undefined)
        .assertTrue();
      replacement.dispose();
      context.close();
      replacementContext.close();
    });

    it('advertisesOnlyTheInjectedRegistrysHandlersForSameAppIdSessions', 0, () => {
      const firstContext = new VkTestSession();
      const secondContext = new VkTestSession();
      const first = new VkEventRegistry(firstContext);
      const second = new VkEventRegistry(secondContext);
      first.initHandler([new MixedHandler(firstContext), new VkResponseInterceptor(firstContext, first)]);
      second.initHandler([new ConflictingHandler(secondContext), new VkResponseInterceptor(secondContext, second)]);
      const firstProxy = new VkBridgeProxy(firstContext, first);
      const secondProxy = new VkBridgeProxy(secondContext, second);
      const request = '{"type":"SetSupportedHandlers","data":{"supportedHandlers":[]}}';
      expect(JSON.stringify(firstProxy.onInterceptResponse(request).data)).assertEqual(
        '{"type":"SetSupportedHandlers","data":{"supportedHandlers":["VKWebAppInit","VKWebAppGetConfig","VKWebAppGetUserInfo","Shared"]}}');
      expect(JSON.stringify(secondProxy.onInterceptResponse(request).data)).assertEqual(
        '{"type":"SetSupportedHandlers","data":{"supportedHandlers":["VKWebAppInit","VKWebAppGetConfig","VKWebAppGetUserInfo","NewRequest"]}}');
      first.dispose();
      expect(JSON.stringify(secondProxy.onInterceptResponse(request).data)).assertEqual(
        '{"type":"SetSupportedHandlers","data":{"supportedHandlers":["VKWebAppInit","VKWebAppGetConfig","VKWebAppGetUserInfo","NewRequest"]}}');
      second.dispose();
      firstContext.close();
      secondContext.close();
    });

    it('doesNotDispatchThroughARegistryOwnedByAnotherContext', 0, () => {
      const owner = new VkTestSession();
      const other = new VkTestSession();
      const registry = new VkEventRegistry(owner);
      registry.initHandler([new MixedHandler(owner)]);
      const proxy = new VkBridgeProxy(other, registry);
      expect(proxy.onInterceptRequest(
        '{"type":"vk-connect","handler":"Shared","params":{"value":"test"}}', 'mismatch').intercept).assertFalse();
      expect(proxy.onInterceptResponse('{"type":"Shared","data":{"value":"test"}}').data === undefined).assertTrue();
      proxy.dispose();
      expect(registry.isActiveFor(owner)).assertTrue();
      registry.dispose();
      owner.close();
      other.close();
    });
  });
}
