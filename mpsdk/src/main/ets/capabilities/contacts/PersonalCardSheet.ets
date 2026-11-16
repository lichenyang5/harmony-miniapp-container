import { common } from '@kit.AbilityKit';
import { ComponentContent, window } from '@kit.ArkUI';
import { assertHostForeground } from '../../core/HostLifecycleMonitor';
import { MiniAppError } from '../../core/MiniAppError';
import { CAPABILITY_BUSY, NOT_SUPPORTED, SESSION_CLOSED, USER_CANCELLED } from '../../core/MiniAppErrorCode';
import { PersonalCardAddressValue, PersonalCardChoice, PersonalCardEntry } from './PersonalCardStore';

const CATEGORY_OPTIONS: string[] = ['personal', 'home', 'work'];
const NEW_CATEGORY_INDEX: number = 3;

export class SheetState {
  saved: PersonalCardEntry[] = [];
  phoneRequested: boolean = false;
  emailRequested: boolean = false;
  addressRequested: boolean = false;
  settled: boolean = false;

  prefill: () => Promise<PersonalCardEntry | undefined> =
    (): Promise<PersonalCardEntry | undefined> => Promise.resolve(undefined);

  finish: (choice: PersonalCardChoice) => void = (): void => {
  };

  cancel: () => void = (): void => {
  };

  abort: (error: MiniAppError) => void = (): void => {
  };
}

@Builder
function personalCardSheetBuilder(state: SheetState) {
  PersonalCardSheetView({ state: state })
}

@Component
struct PersonalCardSheetView {
  state: SheetState = new SheetState();
  @State inDetail: boolean = false;
  @State editing: boolean = false;
  @State categoryIndex: number = 0;
  @State customCategory: string = '';
  @State phoneText: string = '';
  @State emailText: string = '';
  @State countryText: string = '';
  @State cityText: string = '';
  @State specifiedText: string = '';
  @State postalText: string = '';
  @State picking: boolean = false;

  aboutToAppear(): void {
    this.inDetail = this.state.saved.length === 0;
  }

  @Builder
  caption(label: string) {
    Text(label)
      .fontSize(13)
      .fontColor('#8A8A8A')
      .alignSelf(ItemAlign.Start)
  }

  build() {
    Column({ space: 14 }) {
      Text('Personal card')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .alignSelf(ItemAlign.Start)
      if (this.inDetail) {
        this.detailView()
      } else {
        this.listView()
      }
    }
    .padding(20)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(Color.White)
    .borderRadius({ topLeft: 16, topRight: 16 })
  }

  @Builder
  listView() {
    Text('Choose a saved card or add a new one')
      .fontSize(13)
      .fontColor('#8A8A8A')
      .alignSelf(ItemAlign.Start)
    ForEach(this.state.saved, (entry: PersonalCardEntry, index: number) => {
      Row() {
        Text(this.describe(entry))
          .fontSize(16)
          .layoutWeight(1)
        Text('\u203A')
          .fontSize(20)
          .fontColor('#8A8A8A')
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .onClick(() => {
        this.openDetail(entry, true);
      })
    }, (entry: PersonalCardEntry, index: number) => index.toString() + this.describe(entry))
    Button('Add new card')
      .width('100%')
      .onClick(() => {
        this.openDetail(undefined, false);
      })
    Button('Cancel')
      .width('100%')
      .backgroundColor('#F0F0F0')
      .fontColor('#333333')
      .onClick(() => {
        this.state.cancel();
      })
  }

  @Builder
  detailView() {
    if (this.state.phoneRequested) {
      this.caption('Category')
      Select(this.categoryOptions())
        .selected(this.categoryIndex)
        .width('100%')
        .onSelect((index: number) => {
          this.categoryIndex = index;
        })
      if (this.categoryIndex === NEW_CATEGORY_INDEX) {
        this.caption('New category name')
        TextInput({ placeholder: 'Enter a category', text: this.customCategory })
          .onChange((value: string) => {
            this.customCategory = value;
          })
      }
      this.caption('Phone')
      TextInput({ placeholder: 'Enter phone number', text: this.phoneText })
        .type(InputType.PhoneNumber)
        .onChange((value: string) => {
          this.phoneText = value;
        })
    }
    if (this.state.emailRequested) {
      this.caption('Email')
      TextInput({ placeholder: 'Enter email', text: this.emailText })
        .type(InputType.Email)
        .onChange((value: string) => {
          this.emailText = value;
        })
    }
    if (this.state.addressRequested) {
      this.caption('Country')
      TextInput({ placeholder: 'Country', text: this.countryText })
        .onChange((value: string) => {
          this.countryText = value;
        })
      this.caption('City')
      TextInput({ placeholder: 'City', text: this.cityText })
        .onChange((value: string) => {
          this.cityText = value;
        })
      this.caption('Address')
      TextInput({ placeholder: 'Street address', text: this.specifiedText })
        .onChange((value: string) => {
          this.specifiedText = value;
        })
      this.caption('Postal code')
      TextInput({ placeholder: 'Postal code', text: this.postalText })
        .onChange((value: string) => {
          this.postalText = value;
        })
    }
    Button('Fill from contacts')
      .width('100%')
      .enabled(!this.picking)
      .onClick(() => {
        this.pickFromContacts();
      })
    Row({ space: 12 }) {
      if (this.editing) {
        Button('Back')
          .layoutWeight(1)
          .backgroundColor('#F0F0F0')
          .fontColor('#333333')
          .onClick(() => {
            this.inDetail = false;
          })
      }
      Button('Cancel')
        .layoutWeight(1)
        .backgroundColor('#F0F0F0')
        .fontColor('#333333')
        .onClick(() => {
          this.state.cancel();
        })
      Button('Confirm')
        .layoutWeight(1)
        .onClick(() => {
          this.confirm();
        })
    }
    .width('100%')
  }

  private categoryOptions(): SelectOption[] {
    const options: SelectOption[] = CATEGORY_OPTIONS.map((category: string): SelectOption => {
      const option: SelectOption = { value: category };
      return option;
    });
    const newCategory: SelectOption = { value: 'New category' };
    options.push(newCategory);
    return options;
  }

  private describe(entry: PersonalCardEntry): string {
    const parts: string[] = [];
    if (entry.category.length > 0) {
      parts.push(entry.category);
    }
    if (entry.phone.length > 0) {
      parts.push(entry.phone);
    } else if (entry.email.length > 0) {
      parts.push(entry.email);
    } else if (entry.address !== undefined && entry.address.specifiedAddress.length > 0) {
      parts.push(entry.address.specifiedAddress);
    }
    return parts.join(' ');
  }

  private applyCategory(value: string): void {
    const index = CATEGORY_OPTIONS.indexOf(value);
    if (index >= 0) {
      this.categoryIndex = index;
      this.customCategory = '';
    } else {
      this.categoryIndex = NEW_CATEGORY_INDEX;
      this.customCategory = value;
    }
  }

  private openDetail(entry: PersonalCardEntry | undefined, isEditing: boolean): void {
    if (entry === undefined) {
      this.applyCategory(CATEGORY_OPTIONS[0]);
      this.phoneText = '';
      this.emailText = '';
      this.countryText = '';
      this.cityText = '';
      this.specifiedText = '';
      this.postalText = '';
    } else {
      this.applyCategory(entry.category);
      this.phoneText = entry.phone;
      this.emailText = entry.email;
      const address = entry.address;
      this.countryText = address !== undefined ? address.country : '';
      this.cityText = address !== undefined ? address.city : '';
      this.specifiedText = address !== undefined ? address.specifiedAddress : '';
      this.postalText = address !== undefined ? address.postalCode : '';
    }
    this.editing = isEditing;
    this.inDetail = true;
  }

  private async pickFromContacts(): Promise<void> {
    this.picking = true;
    try {
      const entry = await this.state.prefill();
      if (entry !== undefined) {
        if (entry.phone.length > 0) {
          this.phoneText = entry.phone;
        }
        if (entry.email.length > 0) {
          this.emailText = entry.email;
        }
        if (entry.address !== undefined) {
          this.countryText = entry.address.country;
          this.cityText = entry.address.city;
          this.specifiedText = entry.address.specifiedAddress;
          this.postalText = entry.address.postalCode;
        }
      }
    } catch (_) {
    } finally {
      this.picking = false;
    }
  }

  private resolveCategory(): string {
    return this.categoryIndex === NEW_CATEGORY_INDEX ? this.customCategory : CATEGORY_OPTIONS[this.categoryIndex];
  }

  private confirm(): void {
    const entry = new PersonalCardEntry();
    if (this.state.phoneRequested) {
      const category = this.resolveCategory();
      if (category.length === 0 || this.phoneText.length === 0) {
        return;
      }
      entry.category = category;
      entry.phone = this.phoneText;
    }
    if (this.state.emailRequested) {
      if (this.emailText.length === 0) {
        return;
      }
      entry.email = this.emailText;
    }
    if (this.state.addressRequested) {
      if (this.specifiedText.length === 0) {
        return;
      }
      const address = new PersonalCardAddressValue();
      address.country = this.countryText;
      address.city = this.cityText;
      address.specifiedAddress = this.specifiedText;
      address.postalCode = this.postalText;
      entry.address = address;
    }
    const choice = new PersonalCardChoice();
    choice.entry = entry;
    this.state.finish(choice);
  }
}

/** 系统选择器由原生调用控制；会话释放只阻止交付，原生调用结束才释放占用。 */
export class PersonalCardSheetTools {
  private static readonly activeContexts: Set<common.UIAbilityContext> = new Set<common.UIAbilityContext>();
  private readonly context: common.UIAbilityContext;
  private content?: ComponentContent<SheetState>;
  private state?: SheetState;
  private disposed: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async open(saved: PersonalCardEntry[], phoneRequested: boolean, emailRequested: boolean,
    addressRequested: boolean,
    prefill: () => Promise<PersonalCardEntry | undefined>): Promise<PersonalCardChoice> {
    this.assertOpen();
    assertHostForeground(this.context);
    if (PersonalCardSheetTools.activeContexts.has(this.context)) {
      throw new MiniAppError(CAPABILITY_BUSY, 'Personal card sheet is already open');
    }
    const uiContext = await this.getUiContext();
    const state = new SheetState();
    state.saved = saved;
    state.phoneRequested = phoneRequested;
    state.emailRequested = emailRequested;
    state.addressRequested = addressRequested;
    state.prefill = prefill;
    const content = new ComponentContent<SheetState>(uiContext, wrapBuilder(personalCardSheetBuilder), state);
    PersonalCardSheetTools.activeContexts.add(this.context);
    const result = new Promise<PersonalCardChoice>((resolve, reject) => {
      state.finish = (choice: PersonalCardChoice): void => {
        if (state.settled) {
          return;
        }
        state.settled = true;
        this.release(uiContext, content);
        resolve(choice);
      };
      state.cancel = (): void => {
        if (state.settled) {
          return;
        }
        state.settled = true;
        this.release(uiContext, content);
        reject(new MiniAppError(USER_CANCELLED, 'Personal card sheet dismissed'));
      };
      state.abort = (error: MiniAppError): void => {
        if (state.settled) {
          return;
        }
        state.settled = true;
        this.release(uiContext, content);
        reject(error);
      };
    });
    this.content = content;
    this.state = state;
    try {
      await uiContext.getPromptAction().openCustomDialog(content, {
        alignment: DialogAlignment.Bottom,
        autoCancel: true,
        onWillDismiss: (action: DismissDialogAction): void => {
          action.dismiss();
          state.cancel();
        }
      });
    } catch (error) {
      state.abort(new MiniAppError(NOT_SUPPORTED, 'Personal card sheet cannot open', error as Object));
    }
    return result;
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    const state = this.state;
    this.state = undefined;
    this.content = undefined;
    if (state === undefined || state.settled) {
      return;
    }
    state.abort(new MiniAppError(SESSION_CLOSED, 'Personal card sheet is closed'));
  }

  private release(uiContext: UIContext, content: ComponentContent<SheetState>): void {
    this.content = undefined;
    this.state = undefined;
    PersonalCardSheetTools.activeContexts.delete(this.context);
    try {
      uiContext.getPromptAction().closeCustomDialog(content);
    } catch (_) {
    }
  }

  private async getUiContext(): Promise<UIContext> {
    try {
      const hostWindow = await window.getLastWindow(this.context);
      return hostWindow.getUIContext();
    } catch (error) {
      throw new MiniAppError(NOT_SUPPORTED, 'Host window is unavailable', error as Object);
    }
  }

  private assertOpen(): void {
    if (this.disposed) {
      throw new MiniAppError(SESSION_CLOSED, 'Personal card sheet is closed');
    }
  }
}
