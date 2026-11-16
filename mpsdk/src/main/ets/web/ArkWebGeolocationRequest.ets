import { WebGeolocationRequest } from './SessionWebGeolocationPermissions';

/** 显式适配 ArkWeb 定位回调，不持久化跨文档的网站授权。 */
export class ArkWebGeolocationRequest implements WebGeolocationRequest {
  readonly origin: string;
  private readonly geolocation: JsGeolocation;

  constructor(origin: string, geolocation: JsGeolocation) {
    this.origin = origin;
    this.geolocation = geolocation;
  }

  finish(allow: boolean): void {
    this.geolocation.invoke(this.origin, allow, false);
  }
}
