export enum VkClientErrorCode {
  UNKNOWN = 1,
  MISSING_REQUIRED_PARAMS = 2,
  CONNECTION_LOST = 3,
  USER_DENIED = 4,
  INVALID_PARAMS = 5,
  UNSUPPORTED_PLATFORM = 6,
  NO_DEVICE_PERMISSION = 7,
  NEED_USER_PERMISSION = 8,
  BACKGROUND = 9,
  REQUESTS_LIMIT_REACHED = 10,
  ACCESS_DENIED = 11,
  UNINITIALIZED_APP = 12,
  CUSTOM = 13,
  NO_ADS = 20
}

export function vkClientErrorReason(code: VkClientErrorCode): string {
  switch (code) {
    case VkClientErrorCode.UNKNOWN:
      return 'Unknown error';
    case VkClientErrorCode.MISSING_REQUIRED_PARAMS:
      return 'Missing required params';
    case VkClientErrorCode.CONNECTION_LOST:
      return 'Connection lost';
    case VkClientErrorCode.USER_DENIED:
      return 'User denied';
    case VkClientErrorCode.INVALID_PARAMS:
      return 'Invalid params';
    case VkClientErrorCode.UNSUPPORTED_PLATFORM:
      return 'Unsupported platform';
    case VkClientErrorCode.NO_DEVICE_PERMISSION:
      return 'No device permission';
    case VkClientErrorCode.NEED_USER_PERMISSION:
      return 'Need user permission';
    case VkClientErrorCode.BACKGROUND:
      return 'This action cannot be performed in the background';
    case VkClientErrorCode.REQUESTS_LIMIT_REACHED:
      return 'Requests limit reached';
    case VkClientErrorCode.ACCESS_DENIED:
      return 'Access denied';
    case VkClientErrorCode.UNINITIALIZED_APP:
      return 'Uninitialized app';
    case VkClientErrorCode.CUSTOM:
      return 'Custom error for every handler';
    case VkClientErrorCode.NO_ADS:
      return 'No ads';
    default:
      return 'Unknown error';
  }
}
