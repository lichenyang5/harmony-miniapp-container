import { WebMediaRequest } from './WebMediaPermissionController';

/** 显式实现内部接口，避免 ArkTS 将平台 PermissionRequest 作结构类型转换。 */
export class ArkWebMediaRequest implements WebMediaRequest {
  private readonly request: PermissionRequest;

  constructor(request: PermissionRequest) {
    this.request = request;
  }

  getOrigin(): string {
    return this.request.getOrigin();
  }

  getAccessibleResource(): string[] {
    return this.request.getAccessibleResource();
  }

  grant(resources: string[]): void {
    this.request.grant(resources);
  }

  deny(): void {
    this.request.deny();
  }
}
