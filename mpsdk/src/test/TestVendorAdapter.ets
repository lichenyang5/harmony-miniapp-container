import { MiniAppAdapter } from '../main/ets/core/MiniAppAdapter';

class EmptyTestHost {
}

export class TestVendorAdapter extends MiniAppAdapter<EmptyTestHost> {
  readonly vendorId: string;

  constructor(vendorId: string) {
    super(new EmptyTestHost());
    this.vendorId = vendorId;
  }
}
