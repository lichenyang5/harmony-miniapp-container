export enum LineScanResultAction {
  CLOSE,
  COPY,
  OPEN
}

export interface LineScanResultViewParams {
  value: string;
  isLink: boolean;
  complete: (action: LineScanResultAction) => void;
}
