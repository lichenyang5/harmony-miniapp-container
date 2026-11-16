import { resourceManager } from '@kit.LocalizationKit';
import { util } from '@kit.ArkTS';

/** 同步读取随应用打包的小型 UTF-8 资源；异常由调用方处理。 */
export class ResourceUtils {
  static readText(manager: resourceManager.ResourceManager, path: string): string {
    const bytes: Uint8Array = manager.getRawFileContentSync(path);
    return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes);
  }
}
