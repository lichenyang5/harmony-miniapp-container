import { VkBridgeError, VkClientErrorData } from '../main/ets/vendors/vk/VkBridgeError';

export function vkClientCode(error: Object | undefined): string {
  if (!(error instanceof VkBridgeError)) {
    throw new Error('Expected VkBridgeError');
  }
  const failure = error.toData();
  if (failure.error_type !== 'client_error') {
    throw new Error('Expected client_error');
  }
  return String((failure.error_data as VkClientErrorData).error_code);
}
