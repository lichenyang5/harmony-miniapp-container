import { VkEvent } from '../../src/main/ets/vendors/vk/events/VkEvent';

interface Params { value: string; }

interface Result { result: boolean; }

class ValidHandler {
  @VkEvent({ name: 'Custom', resultEvent: 'Received', failureEvent: 'Rejected' })
  async execute(_params: Params): Promise<Result> {
    return { result: true };
  }

  // @ts-expect-error Event names must be strings.
  @VkEvent({ name: 'WrongName', failureEvent: 5 })
  async wrongName(_params: Params): Promise<Result> {
    return { result: true };
  }

  // @ts-expect-error Handler parameters must remain objects.
  @VkEvent({ name: 'Primitive' })
  async primitive(_params: number): Promise<Result> {
    return { result: true };
  }

  // @ts-expect-error Results are business objects, not primitive values.
  @VkEvent({ name: 'PrimitiveResult' })
  async primitiveResult(_params: Params): Promise<number> {
    return 1;
  }
}

export { ValidHandler };
