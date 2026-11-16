import { MiniAppError } from '../main/ets/core/MiniAppError';
import { vkClientCode } from './VkErrorTestUtils';
import { describe, expect, it } from '@ohos/hypium';
import { VkCodeReaderResult, VkMediaHandler } from '../main/ets/vendors/vk/handlers/VkMediaHandler';
import { EmptyParams, VkTestContext } from './TestContext';

class MediaContext extends VkTestContext {
  documentId: number = 1;

  getDocumentId(): number {
    return this.documentId;
  }
}

async function failure(operation: Promise<VkCodeReaderResult>): Promise<string> {
  try {
    await operation;
  } catch (error) {
    return error instanceof MiniAppError && error.code === 'INVALID_ARGUMENT' ? error.code :
      vkClientCode(error as Object);
  }
  return '';
}

export default function vkMediaHandlerTest(): void {
  describe('VkMediaHandler', () => {
    it('rejectsCallsAfterDispose', 0, async () => {
      const handler = new VkMediaHandler(new MediaContext());
      handler.dispose();
      handler.dispose();
      expect(await failure(handler.openCodeReader(new EmptyParams()))).assertEqual('1');
    });

    it('rejectsInvalidParamsBeforeCreatingScanner', 0, async () => {
      const handler = new VkMediaHandler(new MediaContext());
      expect(await failure(handler.openCodeReader(JSON.parse('[]') as object))).assertEqual('INVALID_ARGUMENT');
      handler.dispose();
    });
  });
}
