/** 参数必须为对象；具体字段由事件模块声明并在运行时校验。 */
export type VkEventCallback<TParams extends object = object> = (params: TParams) => Promise<object>;
