unit uViewer;

{$mode delphi}{$H+}

interface

uses Windows;

function CreateCsvViewer(ParentWin: HWND; const FileName: UnicodeString;
  ShowFlags: Integer): HWND;
procedure CloseCsvViewer(Wnd: HWND);
function SearchCsvViewer(Wnd: HWND; const SearchText: UnicodeString;
  SearchFlags: Integer): Integer;

implementation

uses SysUtils, CommCtrl, CommDlg, ShellApi, uSettings, uCsvModel, uCsvSave,
  uGridModel, uColumnSample, uUrlTools, uTransform, uDecimalAlign, listplug;

const
  CSV_VIEWER_CLASS = 'CsvTabMigrationViewer';
  // Posted to the viewer after creation so the grid takes focus only once
  // ListLoadW has returned and TC has finished loading; focusing synchronously
  // during ListLoadW makes TC refresh both file panels.
  WM_CSV_SETFOCUS = WM_USER + 101;
  IDT_INITIAL_LOAD = 1;
  IDT_VALUE_DECODE = 2;
  LCP_FORCESHOW = 16;
  IDC_GRID = 1001;
  IDC_STATUS = 1002;
  IDC_LOADING = 1003;
  IDC_FILTER_BASE = 2000;
  IDC_CELL_EDITOR = 4000;
  IDM_COPY_CELL = 5000;
  IDM_COPY_ROWS = 5001;
  IDM_COPY_COLUMN = 5002;
  IDM_FILTER_ROW = 5003;
  IDM_HEADER_ROW = 5004;
  IDM_DARK_THEME = 5005;
  IDM_LINE_NUMBERS = 5006;
  IDM_DELETE_ROW = 5007;
  IDM_HIDE_COLUMN = 5008;
  IDM_SHOW_COLUMNS = 5009;
  IDM_INSERT_ROW_BELOW = 5034;
  IDM_DELETE_COLUMN = 5043;
  IDM_EDIT_MODE = 5040;
  IDM_SAVE = 5041;
  IDM_TRANSFORM_MODE = 5042;
  LVSICF_NOSCROLL_FLAG = $0002;
  HDF_SORTDOWN_FLAG = $0200;
  HDF_SORTUP_FLAG = $0400;
  IDM_ENCODING_ANSI = 5010;
  IDM_ENCODING_UTF8 = 5011;
  IDM_ENCODING_UTF16LE = 5012;
  IDM_ENCODING_UTF16BE = 5013;
  IDM_DELIMITER_COMMA = 5020;
  IDM_DELIMITER_SEMICOLON = 5021;
  IDM_DELIMITER_VBAR = 5022;
  IDM_DELIMITER_TAB = 5023;
  IDM_DELIMITER_COLON = 5024;
  IDM_DELIMITER_AUTO = 5025;
  IDM_COMMENTS_PARSE = 5030;
  IDM_COMMENTS_NOPARSE = 5031;
  IDM_COMMENTS_HIDE = 5032;
  IDM_COMMENTS_AUTO = 5033;
  CHILD_VIEWER_PROP = 'CsvTabViewer';
  CHILD_WNDPROC_PROP = 'CsvTabOldWndProc';
  IDC_TRANSFORM_LIST = 6000;
  IDC_TRANSFORM_INPUT = 6001;
  IDC_TRANSFORM_UP = 6010;
  IDC_TRANSFORM_DOWN = 6011;
  IDC_TRANSFORM_ADD = 6012;
  IDC_TRANSFORM_REMOVE = 6013;
  IDC_TRANSFORM_RENAME = 6014;
  IDC_TRANSFORM_CONSTANT = 6015;
  IDC_TRANSFORM_FILL = 6016;
  IDC_TRANSFORM_ENUM = 6017;
  IDC_TRANSFORM_LOAD = 6018;
  IDC_TRANSFORM_SAVE = 6019;
  IDC_TRANSFORM_EXPORT = 6020;
  IDC_TRANSFORM_DELIMITER = 6021;
  IDC_TRANSFORM_NUMBER = 6022;
  IDC_TRANSFORM_APPLY = 6023;

type
  THwndArray = array of HWND;
  TBooleanArray = array of Boolean;
  TIntegerArray = array of Integer;
  TSetWindowTheme = function(Wnd: HWND; SubAppName, SubIdList: PWideChar):
    HRESULT; stdcall;

  // Fixed Win32 ABI layout of DRAWITEMSTRUCT, declared locally so the code does
  // not depend on the FPC field name for the device context (hDC vs _hDC).
  TCsvDrawItem = record
    CtlType: UINT;
    CtlID: UINT;
    ItemID: UINT;
    ItemAction: UINT;
    ItemState: UINT;
    HwndItem: HWND;
    DC: HDC;
    RcItem: TRect;
    ItemData: PtrUInt;
  end;
  PCsvDrawItem = ^TCsvDrawItem;

  TCsvViewer = class
  private
    FGrid: HWND;
    FLoading: HWND;
    FStatus: HWND;
    FHeader: HWND;
    FFilterEdits: THwndArray;
    FHiddenColumns: TBooleanArray;
    FFilterRow: Boolean;
    FTextColor: COLORREF;
    FBackColor: COLORREF;
    FBackColor2: COLORREF;
    FFilterTextColor: COLORREF;
    FFilterBackColor: COLORREF;
    FHeaderTextColor: COLORREF;
    FHeaderBackColor: COLORREF;
    FCurrentCellColor: COLORREF;
    FSelectionTextColor: COLORREF;
    FSelectionBackColor: COLORREF;
    FLineNumberTextColor: COLORREF;
    FLineNumberBackColor: COLORREF;
    FLoadingBrush: HBRUSH;
    FFilterBrush: HBRUSH;
    FGridFont: HFONT;
    FHeaderFont: HFONT;
    FFontName: UnicodeString;
    FFontSize: Integer;
    FFontWeight: Integer;
    FInitialAutoSizeDone: Boolean;
    FGridMenu: HMENU;
    FEncodingMenu: HMENU;
    FDelimiterMenu: HMENU;
    FCommentMenu: HMENU;
    FTransform: TTransformConfig;
    FTransformMode: Boolean;
    FTransformList: HWND;
    FTransformInput: HWND;
    FTransformButtons: THwndArray;
    FCellEditor: HWND;
    FEditorOldProc: PtrInt;
    FEditorRow: Integer;
    FEditorColumn: Integer;
    FEditMode: Boolean;
    FDirty: Boolean;
    FClosingEditor: Boolean;
    FConfirmingClose: Boolean;
    FEncodingChoice: UnicodeString;
    FDelimiterChoice: WideChar;
    FDelimiterAuto: Boolean;
    FSkipComments: Integer;
    FCommentsAuto: Boolean;
    FModel: TCsvGridModel;
    FCurrentRow: Integer;
    FCurrentColumn: Integer;
    FSearchText: UnicodeString;
    FSearchFlags: Integer;
    FSearchRow: Integer;
    FSearchColumn: Integer;
    FSearchCellPos: Integer;
    FTransformApplied: Boolean;
    FShowLineNumbers: Boolean;
    FDecimalAlign: Boolean;
    FDecimalAnchors: TIntegerArray;
    FDecimalColumns: TBooleanArray;
    FNumericColumns: TBooleanArray;
    FForwardKeysAfter: QWord;
    FLoaded: Boolean;
    FTakeInitialFocus: Boolean;
    function NumberOffset: Integer;
    function ActiveColumnCount: Integer;
    function ActiveHeaderText(Col: Integer): UnicodeString;
    function ActiveCellText(VisibleRow, Col: Integer): UnicodeString;
    function CalculateColumnWidths: TIntegerArray;
    procedure BuildGrid(const Widths: TIntegerArray);
    procedure LoadInitialDocument;
    procedure StartValueDecodeTimer;
    procedure DecodeValueBatch;
    procedure BuildFilterEdits;
    procedure LayoutFilterEdits;
    procedure ApplyFilter(Column: Integer);
    procedure ApplyTheme;
    procedure UpdateHeaderSortIndicators;
    function CustomDraw(Draw: PNMLVCustomDraw): LRESULT;
    function HeaderCustomDraw(Draw: PNMCustomDraw): LRESULT;
    procedure SubclassChild(Child: HWND);
    procedure AutoSizeColumns;
    procedure UpdateDecimalAnchors;
    procedure Layout;
    procedure SortColumn(Column: Integer);
    function ReloadDocument: Boolean;
    procedure CreateStatusMenus;
    procedure ShowStatusMenu(Part: Integer);
    procedure HandleStatusCommand(Command: Integer);
    procedure CopyCell;
    procedure CopyRows;
    procedure CopyColumn;
    procedure HandleCopyKey;
    procedure CreateGridMenu;
    procedure ShowGridMenu;
    procedure HandleGridCommand(Command: Integer);
    procedure CreateTransformSidebar;
    procedure RefreshTransformSidebar;
    procedure HandleTransformCommand(Command: Integer);
    procedure DrawTransformButton(Item: PCsvDrawItem);
    procedure HideColumn(Column: Integer);
    procedure ShowAllColumns;
    procedure SetFontSize(NewSize: Integer);
    procedure OpenCellUrl(Row, Column: Integer);
    function MoveCurrentCell(Key: WPARAM): Boolean;
    procedure BeginCellEdit(Row, Column: Integer);
    procedure CloseCellEdit(Accept: Boolean);
    function ApplyCellEdit(Row, Column: Integer; const Value: UnicodeString): Boolean;
    procedure InsertRowBelowCurrent;
    procedure DeleteSelectedRows;
    procedure DeleteCurrentColumn;
    function HandleEditKey(Key: WPARAM): Boolean;
    function SaveChanges: Boolean;
    function ConfirmChanges(const ActionText: UnicodeString): Boolean;
    procedure UpdateLoadingStatus;
    procedure UpdateStatus;
  public
    Wnd: HWND;
    FileName: UnicodeString;
    Doc: TCsvDocument;
    destructor Destroy; override;
    function Search(const SearchText: UnicodeString; SearchFlags: Integer): Integer;
  end;

procedure DisableWindowTheme(Wnd: HWND);
var
  Lib: HMODULE;
  SetTheme: TSetWindowTheme;
  EmptyTheme: UnicodeString;
begin
  Lib := LoadLibraryW('uxtheme.dll');
  if Lib = 0 then Exit;
  try
    SetTheme := TSetWindowTheme(GetProcAddress(Lib, 'SetWindowTheme'));
    if Assigned(SetTheme) then
    begin
      EmptyTheme := ' ';
      SetTheme(Wnd, PWideChar(EmptyTheme), PWideChar(EmptyTheme));
    end;
  finally
    FreeLibrary(Lib);
  end;
end;

destructor TCsvViewer.Destroy;
begin
  if IsWindow(Wnd) then KillTimer(Wnd, IDT_INITIAL_LOAD);
  if IsWindow(Wnd) then KillTimer(Wnd, IDT_VALUE_DECODE);
  CloseCellEdit(False);
  if FLoadingBrush <> 0 then DeleteObject(FLoadingBrush);
  if FFilterBrush <> 0 then DeleteObject(FFilterBrush);
  if FHeaderFont <> 0 then DeleteObject(FHeaderFont);
  if FGridFont <> 0 then DeleteObject(FGridFont);
  if FGridMenu <> 0 then DestroyMenu(FGridMenu);
  if FEncodingMenu <> 0 then DestroyMenu(FEncodingMenu);
  if FDelimiterMenu <> 0 then DestroyMenu(FDelimiterMenu);
  if FCommentMenu <> 0 then DestroyMenu(FCommentMenu);
  FTransform.Free;
  FModel.Free;
  Doc.Free;
  inherited Destroy;
end;

function EditorWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM;
  LParam: LPARAM): LRESULT; stdcall; forward;
procedure SetMenuCheck(Menu: HMENU; Command: UINT; Checked: Boolean); forward;

procedure ShowCsvLoadError(Wnd: HWND; const DefaultText: UnicodeString);
var
  MessageText: UnicodeString;
begin
  MessageText := LastCsvLoadError;
  if MessageText = '' then MessageText := DefaultText;
  MessageBoxW(Wnd, PWideChar(MessageText), 'csvtab', MB_OK or MB_ICONERROR);
end;

function IsSeparateListerMode(ParentWin: HWND; ShowFlags: Integer): Boolean;
var
  Root: HWND;
  Style: PtrUInt;
begin
  if (ShowFlags and LCP_FORCESHOW) <> 0 then Exit(True);
  Root := GetAncestor(ParentWin, GA_ROOT);
  if (ParentWin <> 0) and (Root = ParentWin) then Exit(True);
  Style := PtrUInt(GetWindowLongPtrW(ParentWin, GWL_STYLE));
  Result := (Style and WS_POPUP) <> 0;
end;

function ViewerFromWnd(Wnd: HWND): TCsvViewer;
begin
  Result := TCsvViewer(GetWindowLongPtrW(Wnd, GWLP_USERDATA));
end;

function ForwardViewerKey(V: TCsvViewer; Key: WPARAM): Boolean;
var
  FocusWnd, ParentWnd: HWND;
  ScanCode: UINT;
  Ctrl: Boolean;
begin
  Result := False;
  if not Assigned(V) then Exit;
  if GetTickCount64 < V.FForwardKeysAfter then Exit;
  FocusWnd := GetFocus;
  if (FocusWnd <> V.Wnd) and not IsChild(V.Wnd, FocusWnd) then Exit;
  Ctrl := (GetKeyState(VK_CONTROL) and $8000) <> 0;
  if (Key <> VK_ESCAPE) and
    not ((Key = VK_F3) or (Ctrl and (Key = Ord('F'))) or
      ((Key >= Ord('1')) and (Key <= Ord('8')) and not Ctrl and
      (ReadSettingInt('disable-num-keys', 0) = 0)) or
      ((Key = Ord('N')) or (Key = Ord('P'))) and
      (ReadSettingInt('disable-np-keys', 0) = 0) or
      (Key = Ord('Q')) and (ReadSettingInt('exit-by-q', 0) <> 0)) then Exit;
  if (Key <> VK_ESCAPE) and (GetDlgCtrlID(FocusWnd) >= IDC_FILTER_BASE) and
    (GetDlgCtrlID(FocusWnd) < IDC_FILTER_BASE + Length(V.FFilterEdits)) then Exit;
  ParentWnd := GetParent(V.Wnd);
  ScanCode := MapVirtualKey(Key, MAPVK_VK_TO_VSC);
  // Forward exactly one key message without changing TC's active panel.
  PostMessageW(ParentWnd, WM_KEYDOWN, Key, LPARAM(ScanCode) shl 16 or 1);
  Result := True;
end;

function ChildWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM;
  LParam: LPARAM): LRESULT; stdcall;
var
  V: TCsvViewer;
  OldProc: WNDPROC;
  N: PNMHDR;
  IsFilterEdit: Boolean;
  IsTransformControl: Boolean;
  CtlID: Integer;
begin
  V := TCsvViewer(GetPropW(Wnd, CHILD_VIEWER_PROP));
  N := nil;
  CtlID := GetDlgCtrlID(Wnd);
  IsFilterEdit := Assigned(V) and
    (CtlID >= IDC_FILTER_BASE) and
    (CtlID < IDC_FILTER_BASE + Length(V.FFilterEdits));
  IsTransformControl := Assigned(V) and
    ((CtlID = IDC_TRANSFORM_LIST) or (CtlID = IDC_TRANSFORM_INPUT) or
    ((CtlID >= IDC_TRANSFORM_UP) and (CtlID <= IDC_TRANSFORM_APPLY)));
  if Assigned(V) and (Wnd = V.FGrid) and (Msg = WM_NOTIFY) then
  begin
    N := PNMHDR(LParam);
    if Assigned(N) and (N^.hwndFrom = V.FHeader) then
    begin
      if Integer(N^.code) = NM_CUSTOMDRAW then
        Exit(SendMessageW(V.Wnd, WM_NOTIFY, WParam, LParam));
    end;
  end;
  if (Msg = WM_KEYDOWN) and (WParam = VK_ESCAPE) and IsFilterEdit then
  begin
    SetFocus(V.FGrid);
    Exit(0);
  end;
  if (Msg = WM_MOUSEWHEEL) and Assigned(V) and
    ((GetKeyState(VK_CONTROL) and $8000) <> 0) then
  begin
    if SmallInt(HiWord(WParam)) > 0 then V.SetFontSize(V.FFontSize + 1)
    else V.SetFontSize(V.FFontSize - 1);
    Exit(0);
  end;
  if (Msg = WM_KEYDOWN) and Assigned(V) and V.HandleEditKey(WParam) then Exit(0);
  if (Msg = WM_KEYDOWN) and (WParam = Ord('C')) and Assigned(V) and
    not IsFilterEdit and not IsTransformControl then
  begin
    V.HandleCopyKey;
    Exit(0);
  end;
  if (Msg = WM_KEYDOWN) and (WParam = Ord('X')) and Assigned(V) and
    V.FEditMode and not IsFilterEdit and not IsTransformControl and
    (GetKeyState(VK_CONTROL) < 0) then
  begin
    V.DeleteSelectedRows;
    Exit(0);
  end;
  if (Msg = WM_KEYDOWN) and ForwardViewerKey(V, WParam) then Exit(0);
  OldProc := WNDPROC(GetPropW(Wnd, CHILD_WNDPROC_PROP));
  if Assigned(OldProc) then
    Result := CallWindowProcW(OldProc, Wnd, Msg, WParam, LParam)
  else
    Result := DefWindowProcW(Wnd, Msg, WParam, LParam);
  if Assigned(V) and (Wnd = V.FGrid) and
    ((Msg = WM_HSCROLL) or (Msg = LVM_SCROLL) or
     (Msg = LVM_SETCOLUMNWIDTH)) then
    V.LayoutFilterEdits;
  if Assigned(V) and (Wnd = V.FGrid) and (Msg = WM_NOTIFY) and
    Assigned(N) and (N^.hwndFrom = V.FHeader) and
    (Integer(N^.code) <> NM_CUSTOMDRAW) then
  begin
    if Integer(N^.code) = NM_RCLICK then
      SendMessageW(V.Wnd, WM_NOTIFY, WParam, LParam);
    V.LayoutFilterEdits;
  end;
  if Msg = WM_NCDESTROY then
  begin
    RemovePropW(Wnd, CHILD_VIEWER_PROP);
    RemovePropW(Wnd, CHILD_WNDPROC_PROP);
  end;
end;

function EditorWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM;
  LParam: LPARAM): LRESULT; stdcall;
var
  V: TCsvViewer;
  OldProc: WNDPROC;
begin
  V := TCsvViewer(GetPropW(Wnd, CHILD_VIEWER_PROP));
  if Assigned(V) then
  begin
    if (Msg = WM_KEYDOWN) and V.HandleEditKey(WParam) then Exit(0);
    if Msg = WM_KEYDOWN then
    begin
      if WParam = VK_RETURN then begin V.CloseCellEdit(True); Exit(0); end;
      if WParam = VK_ESCAPE then begin V.CloseCellEdit(False); Exit(0); end;
    end;
    if Msg = WM_KILLFOCUS then V.CloseCellEdit(True);
  end;
  OldProc := WNDPROC(GetPropW(Wnd, CHILD_WNDPROC_PROP));
  if Assigned(OldProc) then Result := CallWindowProcW(OldProc, Wnd, Msg, WParam, LParam)
  else Result := DefWindowProcW(Wnd, Msg, WParam, LParam);
end;

procedure TCsvViewer.SubclassChild(Child: HWND);
var
  OldProc: PtrInt;
begin
  if not IsWindow(Child) then Exit;
  SetPropW(Child, CHILD_VIEWER_PROP, THandle(Self));
  OldProc := SetWindowLongPtrW(Child, GWLP_WNDPROC, PtrInt(@ChildWndProc));
  SetPropW(Child, CHILD_WNDPROC_PROP, THandle(OldProc));
end;

procedure TCsvViewer.ApplyTheme;
var
  Dark: Boolean;
  Column: Integer;
begin
  Dark := ReadSettingInt('dark-theme', 0) <> 0;
  if Dark then
  begin
    FTextColor := ReadSettingInt('text-color-dark', 14474460);
    FBackColor := ReadSettingInt('back-color-dark', 2105376);
    FBackColor2 := ReadSettingInt('back-color2-dark', 3421236);
    FFilterTextColor := ReadSettingInt('filter-text-color-dark', 16777215);
    FFilterBackColor := ReadSettingInt('filter-back-color-dark', 3947580);
    FHeaderTextColor := ReadSettingInt('header-text-color-dark', 16777215);
    FHeaderBackColor := ReadSettingInt('header-back-color-dark', 3947580);
    FCurrentCellColor := ReadSettingInt('current-cell-back-color-dark', 4079136);
    FSelectionTextColor := ReadSettingInt('selection-text-color-dark', 14474460);
    FSelectionBackColor := ReadSettingInt('selection-back-color-dark', 6710856);
    FLineNumberTextColor := ReadSettingInt('line-number-text-color-dark', 10395294);
    FLineNumberBackColor := ReadSettingInt('line-number-back-color-dark', 3158064);
  end
  else
  begin
    FTextColor := ReadSettingInt('text-color', 0);
    FBackColor := ReadSettingInt('back-color', 16777215);
    FBackColor2 := ReadSettingInt('back-color2', 15790320);
    FFilterTextColor := ReadSettingInt('filter-text-color', 0);
    FFilterBackColor := ReadSettingInt('filter-back-color', 15790320);
    FHeaderTextColor := ReadSettingInt('header-text-color', 0);
    FHeaderBackColor := ReadSettingInt('header-back-color', 13421772);
    FCurrentCellColor := ReadSettingInt('current-cell-back-color', 10903622);
    FSelectionTextColor := ReadSettingInt('selection-text-color', 16777215);
    FSelectionBackColor := ReadSettingInt('selection-back-color', 6956042);
    FLineNumberTextColor := ReadSettingInt('line-number-text-color', 8421504);
    FLineNumberBackColor := ReadSettingInt('line-number-back-color', 15132390);
  end;
  if FLoadingBrush <> 0 then DeleteObject(FLoadingBrush);
  FLoadingBrush := CreateSolidBrush(FBackColor);
  if FFilterBrush <> 0 then DeleteObject(FFilterBrush);
  FFilterBrush := CreateSolidBrush(FFilterBackColor);
  ListView_SetTextColor(FGrid, FTextColor);
  ListView_SetBkColor(FGrid, FBackColor);
  ListView_SetTextBkColor(FGrid, FBackColor);
  RedrawWindow(FHeader, nil, 0,
    RDW_INVALIDATE or RDW_ERASE or RDW_UPDATENOW);
  RedrawWindow(FGrid, nil, 0,
    RDW_INVALIDATE or RDW_ERASE or RDW_UPDATENOW);
  for Column := 0 to High(FFilterEdits) do
    if IsWindow(FFilterEdits[Column]) then InvalidateRect(FFilterEdits[Column], nil, True);
  if IsWindow(FLoading) then InvalidateRect(FLoading, nil, True);
  InvalidateRect(FStatus, nil, True);
  InvalidateRect(Wnd, nil, True);
end;

procedure TCsvViewer.UpdateHeaderSortIndicators;
var
  Column, DataCol, Count: Integer;
  Item: HD_ITEM;
begin
  if not IsWindow(FHeader) then Exit;
  Count := Header_GetItemCount(FHeader);
  for Column := 0 to Count - 1 do
  begin
    FillChar(Item, SizeOf(Item), 0);
    Item.Mask := HDI_FORMAT;
    if SendMessageW(FHeader, HDM_GETITEMW, Column, LPARAM(@Item)) = 0 then
      Continue;
    Item.fmt := Item.fmt and not (HDF_SORTUP_FLAG or HDF_SORTDOWN_FLAG);
    DataCol := Column - NumberOffset;
    if Assigned(FModel) and (DataCol >= 0) and
      (FModel.SortColumn = DataCol) then
    begin
      if FModel.SortDirection > 0 then
        Item.fmt := Item.fmt or HDF_SORTUP_FLAG
      else if FModel.SortDirection < 0 then
        Item.fmt := Item.fmt or HDF_SORTDOWN_FLAG;
    end;
    SendMessageW(FHeader, HDM_SETITEMW, Column, LPARAM(@Item));
  end;
  InvalidateRect(FHeader, nil, False);
end;

function TCsvViewer.HeaderCustomDraw(Draw: PNMCustomDraw): LRESULT;
var
  Item: HD_ITEM;
  R, ArrowRect: TRect;
  Text: array[0..511] of WideChar;
  OldTextColor, OldBackColor: COLORREF;
  OldFont: HGDIOBJ;
  Brush: HBRUSH;
  Pen, OldPen: HPEN;
  OldBrush: HGDIOBJ;
  Points: array[0..2] of TPoint;
  DataCol, SortDirection, MidX, MidY: Integer;
begin
  Result := CDRF_DODEFAULT;
  if not Assigned(Draw) then Exit;
  if Draw^.dwDrawStage = CDDS_PREPAINT then Exit(CDRF_NOTIFYITEMDRAW);
  if Draw^.dwDrawStage <> CDDS_ITEMPREPAINT then Exit;
  R := Draw^.rc;
  Brush := CreateSolidBrush(FHeaderBackColor);
  FillRect(Draw^.hdc, R, Brush);
  DeleteObject(Brush);
  FillChar(Item, SizeOf(Item), 0);
  FillChar(Text, SizeOf(Text), 0);
  Item.Mask := HDI_TEXT;
  Item.pszText := @Text[0];
  Item.cchTextMax := Length(Text);
  SendMessageW(FHeader, HDM_GETITEMW, PtrUInt(Draw^.dwItemSpec),
    LPARAM(@Item));
  SortDirection := 0;
  DataCol := Integer(Draw^.dwItemSpec) - NumberOffset;
  if Assigned(FModel) and (DataCol >= 0) and
    (FModel.SortColumn = DataCol) then
    SortDirection := FModel.SortDirection;
  InflateRect(R, -6, 0);
  if SortDirection <> 0 then Dec(R.Right, 14);
  OldTextColor := SetTextColor(Draw^.hdc, FHeaderTextColor);
  OldBackColor := SetBkColor(Draw^.hdc, FHeaderBackColor);
  OldFont := SelectObject(Draw^.hdc, FHeaderFont);
  SetBkMode(Draw^.hdc, TRANSPARENT);
  DrawTextW(Draw^.hdc, @Text[0], -1, R,
    DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
  if SortDirection <> 0 then
  begin
    ArrowRect := Draw^.rc;
    ArrowRect.Left := ArrowRect.Right - 16;
    InflateRect(ArrowRect, -4, -4);
    MidX := (ArrowRect.Left + ArrowRect.Right) div 2;
    MidY := (ArrowRect.Top + ArrowRect.Bottom) div 2;
    if SortDirection > 0 then
    begin
      Points[0].X := MidX; Points[0].Y := MidY - 3;
      Points[1].X := MidX - 4; Points[1].Y := MidY + 3;
      Points[2].X := MidX + 4; Points[2].Y := MidY + 3;
    end
    else
    begin
      Points[0].X := MidX; Points[0].Y := MidY + 3;
      Points[1].X := MidX - 4; Points[1].Y := MidY - 3;
      Points[2].X := MidX + 4; Points[2].Y := MidY - 3;
    end;
    Pen := CreatePen(PS_SOLID, 1, FHeaderTextColor);
    Brush := CreateSolidBrush(FHeaderTextColor);
    OldPen := SelectObject(Draw^.hdc, Pen);
    OldBrush := SelectObject(Draw^.hdc, Brush);
    Polygon(Draw^.hdc, Points, Length(Points));
    SelectObject(Draw^.hdc, OldBrush);
    SelectObject(Draw^.hdc, OldPen);
    DeleteObject(Brush);
    DeleteObject(Pen);
  end;
  DrawEdge(Draw^.hdc, Draw^.rc, BDR_SUNKENOUTER, BF_RIGHT or BF_BOTTOM);
  SelectObject(Draw^.hdc, OldFont);
  SetTextColor(Draw^.hdc, OldTextColor);
  SetBkColor(Draw^.hdc, OldBackColor);
  Result := CDRF_SKIPDEFAULT;
end;

function TCsvViewer.CustomDraw(Draw: PNMLVCustomDraw): LRESULT;
var
  Row, Column, Anchor, SavedDC: Integer;
  Selected, CurrentCell: Boolean;
  R, TextRect: TRect;
  Brush: HBRUSH;
  S, IntegerPart, FractionPart, DecimalText: UnicodeString;
  Separator: WideChar;
  OldTextColor: COLORREF;
  OldBkMode: Integer;
  OldFont: HGDIOBJ;
  Pen, OldPen: HPEN;
begin
  Result := CDRF_DODEFAULT;
  if not Assigned(Draw) then Exit;
  if Draw^.nmcd.dwDrawStage = CDDS_PREPAINT then
    Exit(CDRF_NOTIFYITEMDRAW);
  if Draw^.nmcd.dwDrawStage = CDDS_ITEMPREPAINT then
  begin
    Row := Integer(Draw^.nmcd.dwItemSpec);
    Selected := (ListView_GetItemState(FGrid, Row, LVIS_SELECTED) and
      LVIS_SELECTED) <> 0;
    Draw^.clrText := FTextColor;
    if Selected then
    begin
      Draw^.nmcd.uItemState := Draw^.nmcd.uItemState and not CDIS_SELECTED;
      Exit(CDRF_NOTIFYSUBITEMDRAW);
    end;
    if Odd(Row) then Draw^.clrTextBk := FBackColor2
    else Draw^.clrTextBk := FBackColor;
    // The line-number column needs its own colour, so draw subitems even on
    // non-selected rows when it is visible.
    if FShowLineNumbers or FDecimalAlign then Exit(CDRF_NOTIFYSUBITEMDRAW);
    Exit;
  end;
  if Draw^.nmcd.dwDrawStage = (CDDS_ITEMPREPAINT or CDDS_SUBITEM) then
  begin
    Row := Integer(Draw^.nmcd.dwItemSpec);
    if FShowLineNumbers and (Draw^.iSubItem = 0) then
    begin
      // Column 0 ignores LVCFMT_RIGHT in a Win32 list view, so draw the
      // line number ourselves, right-aligned.
      R := Draw^.nmcd.rc;
      R.Right := R.Left + ListView_GetColumnWidth(FGrid, 0);
      Brush := CreateSolidBrush(FLineNumberBackColor);
      FillRect(Draw^.nmcd.hdc, R, Brush);
      DeleteObject(Brush);
      S := ActiveCellText(Row, 0);
      InflateRect(R, -6, 0);
      OldFont := 0;
      if FGridFont <> 0 then OldFont := SelectObject(Draw^.nmcd.hdc, FGridFont);
      OldTextColor := SetTextColor(Draw^.nmcd.hdc, FLineNumberTextColor);
      OldBkMode := SetBkMode(Draw^.nmcd.hdc, TRANSPARENT);
      DrawTextW(Draw^.nmcd.hdc, PWideChar(S), -1, R,
        DT_RIGHT or DT_VCENTER or DT_SINGLELINE);
      SetBkMode(Draw^.nmcd.hdc, OldBkMode);
      SetTextColor(Draw^.nmcd.hdc, OldTextColor);
      if OldFont <> 0 then SelectObject(Draw^.nmcd.hdc, OldFont);
      Exit(CDRF_SKIPDEFAULT);
    end;
    Selected := (ListView_GetItemState(FGrid, Row, LVIS_SELECTED) and
      LVIS_SELECTED) <> 0;
    if Selected then
    begin
      CurrentCell := (Row = FCurrentRow) and
        (Draw^.iSubItem = FCurrentColumn);
      Draw^.clrText := FSelectionTextColor;
      if CurrentCell then Draw^.clrTextBk := FCurrentCellColor
      else Draw^.clrTextBk := FSelectionBackColor;
    end
    else
    begin
      Draw^.clrText := FTextColor;
      if Odd(Row) then Draw^.clrTextBk := FBackColor2
      else Draw^.clrTextBk := FBackColor;
    end;
    Column := Draw^.iSubItem;
    if FDecimalAlign and (not FShowLineNumbers or (Column <> 0)) and
      (Column >= 0) and (Column < Length(FDecimalAnchors)) and
      (Column < Length(FNumericColumns)) and FNumericColumns[Column] then
    begin
      S := ActiveCellText(Row, Column);
      if SplitDecimalText(S, IntegerPart, FractionPart, Separator) or
        IsIntegerText(S) then
      begin
        FillChar(R, SizeOf(R), 0);
        R.Top := Column;
        R.Left := LVIR_BOUNDS;
        if SendMessageW(FGrid, LVM_GETSUBITEMRECT, Row, LPARAM(@R)) = 0 then
          R := Draw^.nmcd.rc;
        if Column = 0 then R.Right := R.Left + ListView_GetColumnWidth(FGrid, 0);
        Brush := CreateSolidBrush(Draw^.clrTextBk);
        FillRect(Draw^.nmcd.hdc, R, Brush);
        DeleteObject(Brush);
        SavedDC := SaveDC(Draw^.nmcd.hdc);
        IntersectClipRect(Draw^.nmcd.hdc, R.Left + 1, R.Top + 1,
          R.Right - 1, R.Bottom - 1);
        OldFont := 0;
        if FGridFont <> 0 then OldFont := SelectObject(Draw^.nmcd.hdc, FGridFont);
        OldTextColor := SetTextColor(Draw^.nmcd.hdc, Draw^.clrText);
        OldBkMode := SetBkMode(Draw^.nmcd.hdc, TRANSPARENT);
        TextRect := R;
        if (Separator = #0) and not FDecimalColumns[Column] then
        begin
          InflateRect(TextRect, -6, 0);
          DrawTextW(Draw^.nmcd.hdc, PWideChar(S), -1, TextRect,
            DT_RIGHT or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
        end
        else
        begin
          Anchor := R.Left + 6 + FDecimalAnchors[Column];
          TextRect.Left := R.Left + 6;
          TextRect.Right := Anchor;
          if Separator = #0 then IntegerPart := Trim(S);
          DrawTextW(Draw^.nmcd.hdc, PWideChar(IntegerPart), -1, TextRect,
            DT_RIGHT or DT_VCENTER or DT_SINGLELINE);
          if Separator <> #0 then
          begin
            DecimalText := Separator + FractionPart;
            TextRect.Left := Anchor;
            TextRect.Right := R.Right - 6;
            DrawTextW(Draw^.nmcd.hdc, PWideChar(DecimalText), -1, TextRect,
              DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
          end;
        end;
        SetBkMode(Draw^.nmcd.hdc, OldBkMode);
        SetTextColor(Draw^.nmcd.hdc, OldTextColor);
        if OldFont <> 0 then SelectObject(Draw^.nmcd.hdc, OldFont);
        RestoreDC(Draw^.nmcd.hdc, SavedDC);
        if (ListView_GetExtendedListViewStyle(FGrid) and LVS_EX_GRIDLINES) <> 0 then
        begin
          Pen := CreatePen(PS_SOLID, 1, GetSysColor(COLOR_3DFACE));
          OldPen := SelectObject(Draw^.nmcd.hdc, Pen);
          MoveToEx(Draw^.nmcd.hdc, R.Right - 1, R.Top, nil);
          LineTo(Draw^.nmcd.hdc, R.Right - 1, R.Bottom);
          MoveToEx(Draw^.nmcd.hdc, R.Left, R.Bottom - 1, nil);
          LineTo(Draw^.nmcd.hdc, R.Right, R.Bottom - 1);
          SelectObject(Draw^.nmcd.hdc, OldPen);
          DeleteObject(Pen);
        end;
        Exit(CDRF_SKIPDEFAULT);
      end;
    end;
  end;
end;

procedure TCsvViewer.Layout;
var
  R, StatusRect: TRect;
  StatusHeight, SidebarWidth, ContentWidth, FilterHeight, I, Top,
    ButtonHeight: Integer;
begin
  if not IsWindow(FGrid) or not IsWindow(FStatus) then Exit;
  GetClientRect(Wnd, R);
  SendMessageW(FStatus, WM_SIZE, 0, 0);
  GetWindowRect(FStatus, StatusRect);
  StatusHeight := StatusRect.Bottom - StatusRect.Top;
  SidebarWidth := 0;
  if FTransformMode then
  begin
    SidebarWidth := 330;
    if SidebarWidth > R.Right div 2 then SidebarWidth := R.Right div 2;
  end;
  ContentWidth := R.Right - SidebarWidth;
  FilterHeight := 0;
  if FLoaded and FFilterRow and not FTransformApplied then FilterHeight := 24;
  if IsWindow(FLoading) then
  begin
    SetWindowPos(FLoading, 0, 0, 0, ContentWidth, R.Bottom - StatusHeight,
      SWP_NOZORDER or SWP_NOACTIVATE);
    if FLoaded then ShowWindow(FLoading, SW_HIDE)
    else ShowWindow(FLoading, SW_SHOW);
  end;
  SetWindowPos(FGrid, 0, 0, FilterHeight, ContentWidth,
    R.Bottom - StatusHeight - FilterHeight,
    SWP_NOZORDER or SWP_NOACTIVATE);
  if FLoaded then ShowWindow(FGrid, SW_SHOW)
  else ShowWindow(FGrid, SW_HIDE);
  if IsWindow(FTransformList) then
  begin
    if FTransformMode then
    begin
      ButtonHeight := 25;
      Top := R.Bottom - StatusHeight - (Length(FTransformButtons) * (ButtonHeight + 3)) - 34;
      if Top < 100 then Top := 100;
      SetWindowPos(FTransformList, 0, ContentWidth + 6, 6,
        SidebarWidth - 12, Top - 12, SWP_NOZORDER or SWP_NOACTIVATE);
      SetWindowPos(FTransformInput, 0, ContentWidth + 6, Top,
        SidebarWidth - 12, 26, SWP_NOZORDER or SWP_NOACTIVATE);
      Inc(Top, 31);
      ShowWindow(FTransformList, SW_SHOW);
      ShowWindow(FTransformInput, SW_SHOW);
      for I := 0 to High(FTransformButtons) do
      begin
        SetWindowPos(FTransformButtons[I], 0, ContentWidth + 6, Top,
          SidebarWidth - 12, ButtonHeight, SWP_NOZORDER or SWP_NOACTIVATE);
        ShowWindow(FTransformButtons[I], SW_SHOW);
        Inc(Top, ButtonHeight + 3);
      end;
    end
    else
    begin
      ShowWindow(FTransformList, SW_HIDE);
      ShowWindow(FTransformInput, SW_HIDE);
      for I := 0 to High(FTransformButtons) do ShowWindow(FTransformButtons[I], SW_HIDE);
    end;
  end;
  LayoutFilterEdits;
end;

procedure TCsvViewer.UpdateLoadingStatus;
var
  Parts: array[0..4] of Integer;
  S: UnicodeString;
begin
  if not IsWindow(FStatus) then Exit;
  Parts[0] := 110;
  Parts[1] := 280;
  Parts[2] := 480;
  Parts[3] := 630;
  Parts[4] := -1;
  SendMessageW(FStatus, SB_SETPARTS, Length(Parts), LPARAM(@Parts[0]));
  S := ' Loading...';
  SendMessageW(FStatus, SB_SETTEXTW, 0, LPARAM(PWideChar(S)));
  SendMessageW(FStatus, SB_SETTEXTW, 1, 0);
  SendMessageW(FStatus, SB_SETTEXTW, 2, 0);
  SendMessageW(FStatus, SB_SETTEXTW, 3, 0);
  SendMessageW(FStatus, SB_SETTEXTW, 4, 0);
end;

procedure TCsvViewer.UpdateStatus;
var
  Parts: array[0..4] of Integer;
  S: UnicodeString;
begin
  if not IsWindow(FStatus) then Exit;
  if (not FLoaded) or not Assigned(Doc) or not Assigned(FModel) then
  begin
    UpdateLoadingStatus;
    Exit;
  end;
  Parts[0] := 110;
  Parts[1] := 280;
  Parts[2] := 480;
  Parts[3] := 630;
  Parts[4] := -1;
  SendMessageW(FStatus, SB_SETPARTS, Length(Parts), LPARAM(@Parts[0]));
  S := ' ' + Doc.Encoding.Name;
  SendMessageW(FStatus, SB_SETTEXTW, 0, LPARAM(PWideChar(S)));
  if Doc.Delimiter = #9 then S := 'TAB'
  else S := String(Doc.Delimiter);
  if FDelimiterAuto then S := ' Delimiter: Auto (' + S + ')'
  else S := ' Delimiter: ' + S;
  SendMessageW(FStatus, SB_SETTEXTW, 1, LPARAM(PWideChar(S)));
  if FCommentsAuto then
    S := Format(' Comments: auto (%d)', [Doc.HiddenCommentCount])
  else
    case FSkipComments of
      1: S := ' Comments: no parse (0)';
      2: S := Format(' Comments: hidden (%d)', [Doc.HiddenCommentCount]);
    else
      S := ' Comments: parse (0)';
    end;
  SendMessageW(FStatus, SB_SETTEXTW, 2, LPARAM(PWideChar(S)));
  S := Format(' Rows: %d/%d', [FModel.VisibleCount,
    Doc.RowCount - Ord(ReadSettingInt('header-row', 1) <> 0)]);
  SendMessageW(FStatus, SB_SETTEXTW, 3, LPARAM(PWideChar(S)));
  if (FCurrentRow >= 0) and (FCurrentColumn >= 0) then
    S := Format(' %d:%d', [FCurrentRow + 1, FCurrentColumn + 1])
  else
    S := '';
  if FEditMode and FDirty then S := S + ' EDIT *'
  else if FEditMode then S := S + ' EDIT'
  else if FDirty then S := S + ' MODIFIED *';
  if FTransformApplied then S := S + ' | TRANSFORM';
  SendMessageW(FStatus, SB_SETTEXTW, 4, LPARAM(PWideChar(S)));
end;

function TCsvViewer.HandleEditKey(Key: WPARAM): Boolean;
begin
  Result := False;
  if Key = VK_F1 then
  begin
    ShellExecuteW(0, 'open', 'https://github.com/little-brother/csvtab-wlx/wiki',
      nil, nil, SW_SHOW);
    Exit(True);
  end;
  if (GetKeyState(VK_CONTROL) < 0) and (Key = VK_ADD) then
  begin
    SetFontSize(FFontSize + 1);
    Exit(True);
  end;
  if (GetKeyState(VK_CONTROL) < 0) and (Key = VK_SUBTRACT) then
  begin
    SetFontSize(FFontSize - 1);
    Exit(True);
  end;
  if (GetKeyState(VK_CONTROL) < 0) and (Key = VK_SPACE) then
  begin
    ShowAllColumns;
    Exit(True);
  end;
  if (GetKeyState(VK_CONTROL) < 0) and (Key = Ord('S')) then
  begin
    SaveChanges;
    Exit(True);
  end;
  if (GetKeyState(VK_CONTROL) < 0) and ((Key = Ord('R')) or (Key = Ord('E'))) then
  begin
    CloseCellEdit(True);
    FEditMode := not FEditMode;
    UpdateStatus;
    Exit(True);
  end;
  if (GetKeyState(VK_CONTROL) < 0) and (Key = Ord('T')) then
  begin
    FTransformMode := not FTransformMode;
    RefreshTransformSidebar;
    Layout;
    Exit(True);
  end;
  if MoveCurrentCell(Key) then Exit(True);
  if (Key = VK_F2) and (GetFocus = FGrid) then
  begin
    BeginCellEdit(FCurrentRow, FCurrentColumn);
    Exit(True);
  end;
  if (Key = VK_RETURN) and FEditMode and (not FTransformApplied) and
    (GetFocus = FGrid) and (FCurrentRow >= 0) and
    (FCurrentRow < FModel.VisibleCount) and
    (FCurrentColumn >= NumberOffset) and
    (FCurrentColumn - NumberOffset < Doc.ColumnCount) then
  begin
    BeginCellEdit(FCurrentRow, FCurrentColumn);
    Exit(True);
  end;
end;

function TCsvViewer.SaveChanges: Boolean;
begin
  CloseCellEdit(True);
  if IsWindow(FCellEditor) then Exit(False);
  if not FDirty then Exit(True);
  Result := SaveCsvSourceAtomic(FileName, Doc.SourceText, Doc.Encoding,
    Doc.Delimiter, FSkipComments, ReadSettingInt('trim-values', 1) <> 0);
  if Result then
  begin
    FDirty := False;
    UpdateStatus;
  end
  else
  begin
    MessageBoxW(Wnd, 'The file could not be saved.', 'csvtab',
      MB_OK or MB_ICONERROR);
    UpdateStatus;
  end;
end;

function TCsvViewer.ConfirmChanges(const ActionText: UnicodeString): Boolean;
var
  Choice: Integer;
  MessageText: UnicodeString;
begin
  Result := False;
  if FConfirmingClose then Exit;
  FConfirmingClose := True;
  try
    CloseCellEdit(True);
    if IsWindow(FCellEditor) then Exit;
    if not FDirty then Exit(True);
    MessageText := 'Save changes to "' + ExtractFileName(FileName) +
      '" before ' + ActionText + '?';
    Choice := MessageBoxW(Wnd, PWideChar(MessageText), 'csvtab',
      MB_YESNO or MB_ICONWARNING or MB_DEFBUTTON1);
    case Choice of
      IDYES: Result := SaveChanges;
      IDNO: Result := True;
    end;
  finally
    FConfirmingClose := False;
  end;
end;

procedure TCsvViewer.BeginCellEdit(Row, Column: Integer);
var
  R: TRect;
  Value: UnicodeString;
  DataCol: Integer;
begin
  if FTransformApplied then Exit;
  CloseCellEdit(True);
  DataCol := Column - NumberOffset;
  if not FEditMode or (Row < 0) or (DataCol < 0) or
    (Row >= FModel.VisibleCount) or (DataCol >= Doc.ColumnCount) then Exit;
  FillChar(R, SizeOf(R), 0);
  R.Top := Column;
  R.Left := LVIR_BOUNDS;
  if SendMessageW(FGrid, LVM_GETSUBITEMRECT, Row, LPARAM(@R)) = 0 then Exit;
  if Column = 0 then R.Right := R.Left + ListView_GetColumnWidth(FGrid, 0);
  Value := FModel.CellText(Row, DataCol);
  FEditorRow := Row;
  FEditorColumn := DataCol;
  FCellEditor := CreateWindowExW(0, WC_EDITW, PWideChar(Value),
    WS_CHILD or WS_VISIBLE or WS_BORDER or ES_AUTOHSCROLL,
    R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top,
    FGrid, IDC_CELL_EDITOR, HInstance, nil);
  if FCellEditor = 0 then Exit;
  SetPropW(FCellEditor, CHILD_VIEWER_PROP, THandle(Self));
  FEditorOldProc := SetWindowLongPtrW(FCellEditor, GWLP_WNDPROC,
    PtrInt(@EditorWndProc));
  SetPropW(FCellEditor, CHILD_WNDPROC_PROP, THandle(FEditorOldProc));
  if FGridFont <> 0 then SendMessageW(FCellEditor, WM_SETFONT, FGridFont, 1);
  SendMessageW(FCellEditor, EM_SETSEL, 0, -1);
  SetFocus(FCellEditor);
  UpdateStatus;
end;

procedure TCsvViewer.CloseCellEdit(Accept: Boolean);
var
  Editor: HWND;
  TextLength: Integer;
  Value: UnicodeString;
begin
  if FClosingEditor or not IsWindow(FCellEditor) then Exit;
  FClosingEditor := True;
  if Accept then
  begin
    TextLength := GetWindowTextLengthW(FCellEditor);
    SetLength(Value, TextLength);
    if TextLength > 0 then GetWindowTextW(FCellEditor, PWideChar(Value), TextLength + 1);
    if not ApplyCellEdit(FEditorRow, FEditorColumn, Value) then
    begin
      FClosingEditor := False;
      MessageBeep(MB_ICONWARNING);
      Exit;
    end;
  end;
  Editor := FCellEditor;
  FCellEditor := 0;
  if FEditorOldProc <> 0 then
    SetWindowLongPtrW(Editor, GWLP_WNDPROC, FEditorOldProc);
  FEditorOldProc := 0;
  RemovePropW(Editor, CHILD_VIEWER_PROP);
  RemovePropW(Editor, CHILD_WNDPROC_PROP);
  DestroyWindow(Editor);
  FClosingEditor := False;
  SetFocus(FGrid);
  UpdateStatus;
end;

function TCsvViewer.ApplyCellEdit(Row, Column: Integer;
  const Value: UnicodeString): Boolean;
var
  SourceRow: Integer;
begin
  Result := False;
  SourceRow := FModel.SourceRowAt(Row);
  if SourceRow < 0 then Exit;
  if not Doc.ApplyCellEdit(SourceRow, Column, Value) then Exit;
  FDirty := True;
  FModel.Rebuild;
  FCurrentRow := -1;
  FCurrentColumn := -1;
  SendMessageW(FGrid, LVM_SETITEMCOUNT, FModel.VisibleCount, 0);
  UpdateDecimalAnchors;
  InvalidateRect(FGrid, nil, False);
  LayoutFilterEdits;
  UpdateStatus;
  Result := True;
end;

procedure TCsvViewer.InsertRowBelowCurrent;
var
  SourceRow, InsertedSourceRow, NewVisibleRow, Row: Integer;
begin
  if FTransformApplied or not FEditMode then Exit; // preview is read-only
  CloseCellEdit(False);
  if (FCurrentRow < 0) or (FCurrentRow >= FModel.VisibleCount) then Exit;
  SourceRow := FModel.SourceRowAt(FCurrentRow);
  if SourceRow < 0 then Exit;
  if not Doc.InsertRowAfter(SourceRow) then Exit;

  FDirty := True;
  InsertedSourceRow := SourceRow + 1;
  FModel.Rebuild;
  SendMessageW(FGrid, LVM_SETITEMCOUNT, FModel.VisibleCount, 0);
  UpdateDecimalAnchors;

  NewVisibleRow := -1;
  for Row := 0 to FModel.VisibleCount - 1 do
    if FModel.SourceRowAt(Row) = InsertedSourceRow then
    begin
      NewVisibleRow := Row;
      Break;
    end;

  ListView_SetItemState(FGrid, -1, 0, LVIS_SELECTED or LVIS_FOCUSED);
  if NewVisibleRow >= 0 then
  begin
    FCurrentRow := NewVisibleRow;
    if FCurrentColumn < NumberOffset then FCurrentColumn := NumberOffset;
    ListView_SetItemState(FGrid, NewVisibleRow, LVIS_SELECTED or LVIS_FOCUSED,
      LVIS_SELECTED or LVIS_FOCUSED);
    ListView_EnsureVisible(FGrid, NewVisibleRow, False);
  end
  else
  begin
    FCurrentRow := -1;
    FCurrentColumn := -1;
  end;

  InvalidateRect(FGrid, nil, True);
  LayoutFilterEdits;
  UpdateStatus;
end;

procedure TCsvViewer.DeleteSelectedRows;
var
  SourceRows: array of Integer;
  Row, I, J, Tmp, Deleted: Integer;
begin
  if FTransformApplied or not FEditMode then Exit; // preview is read-only
  CloseCellEdit(False);
  // Collect the source rows behind the selection; fall back to the cursor row.
  SetLength(SourceRows, 0);
  Row := ListView_GetNextItem(FGrid, -1, LVNI_SELECTED);
  while Row >= 0 do
  begin
    SetLength(SourceRows, Length(SourceRows) + 1);
    SourceRows[High(SourceRows)] := FModel.SourceRowAt(Row);
    Row := ListView_GetNextItem(FGrid, Row, LVNI_SELECTED);
  end;
  if (Length(SourceRows) = 0) and (FCurrentRow >= 0) then
  begin
    SetLength(SourceRows, 1);
    SourceRows[0] := FModel.SourceRowAt(FCurrentRow);
  end;
  if Length(SourceRows) = 0 then Exit;
  // Delete from the highest source row down so earlier indices stay valid.
  for I := 0 to High(SourceRows) - 1 do
    for J := I + 1 to High(SourceRows) do
      if SourceRows[J] > SourceRows[I] then
      begin
        Tmp := SourceRows[I]; SourceRows[I] := SourceRows[J]; SourceRows[J] := Tmp;
      end;
  Deleted := 0;
  for I := 0 to High(SourceRows) do
    if (SourceRows[I] >= 0) and Doc.DeleteRow(SourceRows[I]) then Inc(Deleted);
  if Deleted = 0 then Exit;
  FDirty := True;
  FModel.Rebuild;
  FCurrentRow := -1;
  FCurrentColumn := -1;
  ListView_SetItemState(FGrid, -1, 0, LVIS_SELECTED or LVIS_FOCUSED);
  SendMessageW(FGrid, LVM_SETITEMCOUNT, FModel.VisibleCount, 0);
  InvalidateRect(FGrid, nil, True);
  LayoutFilterEdits;
  UpdateStatus;
end;

procedure TCsvViewer.DeleteCurrentColumn;
var
  DataCol: Integer;
  NewModel: TCsvGridModel;
  HeaderName, MessageText: UnicodeString;
  CaseSensitive: Boolean;
begin
  if FTransformApplied or not FEditMode then Exit; // preview is read-only
  CloseCellEdit(False);
  DataCol := FCurrentColumn - NumberOffset;
  if (DataCol < 0) or (DataCol >= Doc.ColumnCount) then Exit;
  HeaderName := ActiveHeaderText(FCurrentColumn);
  MessageText := 'Delete column "' + HeaderName + '"?';
  if MessageBoxW(Wnd, PWideChar(MessageText), 'csvtab',
    MB_YESNO or MB_ICONWARNING or MB_DEFBUTTON2) <> IDYES then Exit;
  if not Doc.DeleteColumn(DataCol) then Exit;
  FDirty := True;
  CaseSensitive := Assigned(FModel) and FModel.CaseSensitive;
  NewModel := TCsvGridModel.Create(Doc, ReadSettingInt('header-row', 1) <> 0);
  NewModel.CaseSensitive := CaseSensitive;
  FModel.Free;
  FModel := NewModel;
  SetLength(FHiddenColumns, Doc.ColumnCount);
  FCurrentRow := -1;
  FCurrentColumn := -1;
  BuildGrid(CalculateColumnWidths);
  InvalidateRect(FGrid, nil, True);
  LayoutFilterEdits;
  UpdateStatus;
end;

procedure SetClipboardUnicode(Owner: HWND; const Text: UnicodeString);
var
  Memory: HGLOBAL;
  Data: Pointer;
  ByteCount: NativeUInt;
begin
  if not OpenClipboard(Owner) then Exit;
  try
    EmptyClipboard;
    ByteCount := (Length(Text) + 1) * SizeOf(WideChar);
    Memory := GlobalAlloc(GMEM_MOVEABLE, ByteCount);
    if Memory = 0 then Exit;
    Data := GlobalLock(Memory);
    if not Assigned(Data) then
    begin
      GlobalFree(Memory);
      Exit;
    end;
    if Text <> '' then
      Move(PWideChar(Text)^, Data^, Length(Text) * SizeOf(WideChar));
    PWideChar(Data)[Length(Text)] := #0;
    GlobalUnlock(Memory);
    if SetClipboardData(CF_UNICODETEXT, Memory) = 0 then GlobalFree(Memory);
  finally
    CloseClipboard;
  end;
end;

procedure TCsvViewer.CopyCell;
begin
  if (FCurrentRow < 0) or (FCurrentColumn < 0) then
    SetClipboardUnicode(Wnd, '')
  else
    SetClipboardUnicode(Wnd, ActiveCellText(FCurrentRow, FCurrentColumn));
end;

procedure TCsvViewer.CopyRows;
var
  Row, Index, Column, ColumnCount: Integer;
  Order: array of Integer;
  DelimiterText, ResultText, RowText: UnicodeString;
  FirstCell: Boolean;
begin
  ResultText := '';
  DelimiterText := ReadSetting('column-delimiter', #9);
  if DelimiterText = '' then DelimiterText := #9;
  ColumnCount := ActiveColumnCount;
  SetLength(Order, ColumnCount);
  if ColumnCount > 0 then
    Header_GetOrderArray(FHeader, ColumnCount, LPARAM(@Order[0]));
  Row := ListView_GetNextItem(FGrid, -1, LVNI_SELECTED);
  while Row >= 0 do
  begin
    if ResultText <> '' then ResultText := ResultText + #13#10;
    RowText := '';
    FirstCell := True;
    for Index := 0 to ColumnCount - 1 do
    begin
      Column := Order[Index];
      if FShowLineNumbers and (Column = 0) then Continue;
      if ListView_GetColumnWidth(FGrid, Column) = 0 then Continue;
      if not FirstCell then RowText := RowText + DelimiterText[1];
      RowText := RowText + ActiveCellText(Row, Column);
      FirstCell := False;
    end;
    ResultText := ResultText + RowText;
    Row := ListView_GetNextItem(FGrid, Row, LVNI_SELECTED);
  end;
  SetClipboardUnicode(Wnd, ResultText);
end;

procedure TCsvViewer.CopyColumn;
var
  Row, SelectedCount: Integer;
  ResultText: UnicodeString;
begin
  ResultText := '';
  if FCurrentColumn < 0 then
  begin
    SetClipboardUnicode(Wnd, '');
    Exit;
  end;
  SelectedCount := ListView_GetSelectedCount(FGrid);
  if SelectedCount > 1 then Row := ListView_GetNextItem(FGrid, -1, LVNI_SELECTED)
  else Row := 0;
  while (Row >= 0) and (Row < FModel.VisibleCount) do
  begin
    if ResultText <> '' then ResultText := ResultText + #13#10;
    ResultText := ResultText + ActiveCellText(Row, FCurrentColumn);
    if SelectedCount > 1 then Row := ListView_GetNextItem(FGrid, Row, LVNI_SELECTED)
    else Inc(Row);
  end;
  SetClipboardUnicode(Wnd, ResultText);
end;

procedure TCsvViewer.HandleCopyKey;
begin
  if (GetKeyState(VK_SHIFT) < 0) then CopyRows
  else if (GetKeyState(VK_CONTROL) < 0) or
    ((ReadSettingInt('copy-column', 0) <> 0) and
    (ListView_GetSelectedCount(FGrid) > 1)) then CopyColumn
  else CopyCell;
end;

procedure TCsvViewer.HideColumn(Column: Integer);
var
  DataCol: Integer;
begin
  if (Column < 0) or (Column >= ActiveColumnCount) then Exit;
  DataCol := Column - NumberOffset;
  if DataCol < 0 then Exit; // the line-number column cannot be hidden
  if Length(FHiddenColumns) <> ActiveColumnCount - NumberOffset then
    SetLength(FHiddenColumns, ActiveColumnCount - NumberOffset);
  FHiddenColumns[DataCol] := True;
  SendMessageW(FGrid, LVM_SETCOLUMNWIDTH, Column, 0);
  LayoutFilterEdits;
end;

procedure TCsvViewer.ShowAllColumns;
var
  Column: Integer;
begin
  for Column := 0 to High(FHiddenColumns) do FHiddenColumns[Column] := False;
  AutoSizeColumns;
  LayoutFilterEdits;
end;

procedure TCsvViewer.SetFontSize(NewSize: Integer);
var
  DC: HDC;
  FontHeight, Column, I: Integer;
  NewFont, NewHeaderFont: HFONT;
begin
  if (NewSize < 10) or (NewSize > 48) or (NewSize = FFontSize) then Exit;
  DC := GetDC(FGrid);
  if DC <> 0 then
  begin
    FontHeight := -MulDiv(NewSize, GetDeviceCaps(DC, LOGPIXELSY), 72);
    ReleaseDC(FGrid, DC);
  end
  else
    FontHeight := -NewSize;
  NewFont := CreateFontW(FontHeight, 0, 0, 0, FFontWeight, 0, 0, 0,
    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
    DEFAULT_PITCH or FF_DONTCARE, PWideChar(FFontName));
  if NewFont = 0 then Exit;
  NewHeaderFont := CreateFontW(FontHeight, 0, 0, 0, FW_BOLD, 0, 0, 0,
    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
    DEFAULT_PITCH or FF_DONTCARE, PWideChar(FFontName));
  if NewHeaderFont = 0 then
  begin
    DeleteObject(NewFont);
    Exit;
  end;
  SendMessageW(FGrid, WM_SETFONT, WPARAM(NewFont), 1);
  SendMessageW(FHeader, WM_SETFONT, WPARAM(NewHeaderFont), 1);
  for Column := 0 to High(FFilterEdits) do
    if IsWindow(FFilterEdits[Column]) then
      SendMessageW(FFilterEdits[Column], WM_SETFONT, WPARAM(NewFont), 1);
  if IsWindow(FCellEditor) then
    SendMessageW(FCellEditor, WM_SETFONT, WPARAM(NewFont), 1);
  if IsWindow(FTransformList) then
  begin
    SendMessageW(FTransformList, WM_SETFONT, WPARAM(NewFont), 1);
    SendMessageW(FTransformInput, WM_SETFONT, WPARAM(NewFont), 1);
    for I := 0 to High(FTransformButtons) do
      SendMessageW(FTransformButtons[I], WM_SETFONT, WPARAM(NewFont), 1);
  end;
  if FGridFont <> 0 then DeleteObject(FGridFont);
  if FHeaderFont <> 0 then DeleteObject(FHeaderFont);
  FGridFont := NewFont;
  FHeaderFont := NewHeaderFont;
  FFontSize := NewSize;
  WriteSettingInt('font-size', FFontSize);
  UpdateDecimalAnchors;
  Layout;
  InvalidateRect(FGrid, nil, True);
end;

procedure TCsvViewer.OpenCellUrl(Row, Column: Integer);
var
  Url: UnicodeString;
begin
  if (Row < 0) or (Row >= FModel.VisibleCount) or (Column < 0) or
    (Column >= ActiveColumnCount) then Exit;
  Url := ExtractCellUrl(ActiveCellText(Row, Column));
  if Url <> '' then ShellExecuteW(0, 'open', PWideChar(Url), nil, nil, SW_SHOW);
end;

function TCsvViewer.MoveCurrentCell(Key: WPARAM): Boolean;
var
  Row, Column, TargetRow, TargetColumn, Count, I, Dx: Integer;
  CtrlDown: Boolean;
  CellRect, ClientRect: TRect;

  function IsVisibleColumn(AColumn: Integer): Boolean;
  begin
    Result := (AColumn >= 0) and (AColumn < ActiveColumnCount) and
      (ListView_GetColumnWidth(FGrid, AColumn) > 0);
  end;

  function FirstVisibleColumn: Integer;
  var
    C: Integer;
  begin
    Result := -1;
    for C := 0 to ActiveColumnCount - 1 do
      if IsVisibleColumn(C) then Exit(C);
  end;

  function LastVisibleColumn: Integer;
  var
    C: Integer;
  begin
    Result := -1;
    for C := ActiveColumnCount - 1 downto 0 do
      if IsVisibleColumn(C) then Exit(C);
  end;

  function NextVisibleColumn(StartColumn, Direction: Integer): Integer;
  var
    C: Integer;
  begin
    Result := StartColumn;
    C := StartColumn + Direction;
    while (C >= 0) and (C < ActiveColumnCount) do
    begin
      if IsVisibleColumn(C) then Exit(C);
      Inc(C, Direction);
    end;
  end;

  procedure EnsureCurrentCellVisible(HorzDirection: Integer);
  begin
    if (FCurrentRow < 0) or (FCurrentColumn < 0) then Exit;
    ListView_EnsureVisible(FGrid, FCurrentRow, False);
    FillChar(CellRect, SizeOf(CellRect), 0);
    CellRect.Top := FCurrentColumn;
    CellRect.Left := LVIR_BOUNDS;
    if SendMessageW(FGrid, LVM_GETSUBITEMRECT, FCurrentRow,
      LPARAM(@CellRect)) = 0 then Exit;
    if FCurrentColumn = 0 then
      CellRect.Right := CellRect.Left + ListView_GetColumnWidth(FGrid, 0);
    GetClientRect(FGrid, ClientRect);
    Dx := 0;
    if (HorzDirection < 0) and (CellRect.Left < ClientRect.Left) then
      Dx := CellRect.Left - ClientRect.Left
    else if (HorzDirection > 0) and (CellRect.Right > ClientRect.Right) then
      Dx := CellRect.Right - ClientRect.Right
    else if CellRect.Left < ClientRect.Left then
      Dx := CellRect.Left - ClientRect.Left
    else if CellRect.Right > ClientRect.Right then
      Dx := CellRect.Right - ClientRect.Right;
    if Dx <> 0 then
    begin
      SendMessageW(FGrid, LVM_SCROLL, Dx, 0);
      LayoutFilterEdits;
    end;
  end;

begin
  Result := False;
  if (not FLoaded) or (not IsWindow(FGrid)) or (GetFocus <> FGrid) or
    (FModel.VisibleCount <= 0) then Exit;
  if (Key <> VK_UP) and (Key <> VK_DOWN) and (Key <> VK_LEFT) and
    (Key <> VK_RIGHT) then Exit;

  Row := FCurrentRow;
  Column := FCurrentColumn;
  if (Row < 0) or (Row >= FModel.VisibleCount) then
    Row := ListView_GetNextItem(FGrid, -1, LVNI_FOCUSED);
  if (Row < 0) or (Row >= FModel.VisibleCount) then
    Row := ListView_GetNextItem(FGrid, -1, LVNI_SELECTED);
  if (Row < 0) or (Row >= FModel.VisibleCount) then Exit;
  if not IsVisibleColumn(Column) then
  begin
    Column := FirstVisibleColumn;
    if Column < 0 then Exit;
  end;

  CtrlDown := GetKeyState(VK_CONTROL) < 0;
  TargetRow := Row;
  TargetColumn := Column;

  case Key of
    VK_UP:
      if CtrlDown then TargetRow := 0
      else if Row > 0 then TargetRow := Row - 1;
    VK_DOWN:
      begin
        Count := FModel.VisibleCount;
        if CtrlDown then TargetRow := Count - 1
        else if Row < Count - 1 then TargetRow := Row + 1;
      end;
    VK_LEFT:
      if CtrlDown then TargetColumn := FirstVisibleColumn
      else
      begin
        I := NextVisibleColumn(Column, -1);
        if I <> Column then TargetColumn := I;
      end;
    VK_RIGHT:
      if CtrlDown then TargetColumn := LastVisibleColumn
      else
      begin
        I := NextVisibleColumn(Column, 1);
        if I <> Column then TargetColumn := I;
      end;
  end;

  if (TargetRow = Row) and (TargetColumn = Column) then
  begin
    FCurrentRow := Row;
    FCurrentColumn := Column;
    EnsureCurrentCellVisible(0);
    Exit(True);
  end;

  FCurrentRow := TargetRow;
  FCurrentColumn := TargetColumn;
  ListView_SetItemState(FGrid, -1, 0, LVIS_SELECTED or LVIS_FOCUSED);
  ListView_SetItemState(FGrid, FCurrentRow, LVIS_SELECTED or LVIS_FOCUSED,
    LVIS_SELECTED or LVIS_FOCUSED);
  if Key = VK_LEFT then EnsureCurrentCellVisible(-1)
  else if Key = VK_RIGHT then EnsureCurrentCellVisible(1)
  else EnsureCurrentCellVisible(0);
  InvalidateRect(FGrid, nil, False);
  UpdateStatus;
  Result := True;
end;

function SelectTransformFile(Owner: HWND; SaveDialog: Boolean;
  const Filter, Extension: UnicodeString): UnicodeString;
var
  OpenFile: OPENFILENAMEW;
  Buffer: array[0..MAX_PATH * 4] of WideChar;
  FilterText: UnicodeString;
begin
  Result := '';
  FillChar(OpenFile, SizeOf(OpenFile), 0);
  FillChar(Buffer, SizeOf(Buffer), 0);
  FilterText := Filter + #0 + '*.' + Extension + #0 + 'All files' + #0 + '*.*' + #0#0;
  OpenFile.lStructSize := SizeOf(OpenFile);
  OpenFile.hwndOwner := Owner;
  OpenFile.lpstrFilter := PWideChar(FilterText);
  OpenFile.lpstrFile := @Buffer[0];
  OpenFile.nMaxFile := Length(Buffer);
  OpenFile.lpstrDefExt := PWideChar(Extension);
  OpenFile.Flags := OFN_EXPLORER or OFN_PATHMUSTEXIST or OFN_HIDEREADONLY;
  if SaveDialog then
  begin
    OpenFile.Flags := OpenFile.Flags or OFN_OVERWRITEPROMPT;
    if not GetSaveFileNameW(@OpenFile) then Exit;
  end
  else if not GetOpenFileNameW(@OpenFile) then Exit;
  Result := Buffer;
end;

function WindowText(Wnd: HWND): UnicodeString;
var
  Count: Integer;
begin
  Count := GetWindowTextLengthW(Wnd);
  SetLength(Result, Count);
  if Count > 0 then GetWindowTextW(Wnd, PWideChar(Result), Count + 1);
end;

function TransformGroupColor(CtlID: Integer): COLORREF;
begin
  // Each visual group of related actions gets its own pastel background.
  case CtlID of
    IDC_TRANSFORM_UP, IDC_TRANSFORM_DOWN:
      Result := RGB(208, 228, 246);                          // blue - ordering
    IDC_TRANSFORM_ADD, IDC_TRANSFORM_REMOVE, IDC_TRANSFORM_RENAME:
      Result := RGB(212, 237, 218);                          // green - columns
    IDC_TRANSFORM_CONSTANT, IDC_TRANSFORM_FILL, IDC_TRANSFORM_ENUM:
      Result := RGB(255, 242, 204);                          // yellow - cell values
    IDC_TRANSFORM_LOAD, IDC_TRANSFORM_SAVE:
      Result := RGB(228, 216, 244);                          // purple - load/save
    IDC_TRANSFORM_EXPORT, IDC_TRANSFORM_DELIMITER, IDC_TRANSFORM_NUMBER:
      Result := RGB(210, 236, 240);                          // cyan - export
  else
    Result := GetSysColor(COLOR_BTNFACE);                    // apply - default
  end;
end;

procedure TCsvViewer.DrawTransformButton(Item: PCsvDrawItem);
var
  R: TRect;
  Brush: HBRUSH;
  Pressed: Boolean;
  Caption: array[0..255] of WideChar;
  OldBkMode: Integer;
  OldTextColor: COLORREF;
begin
  if not Assigned(Item) then Exit;
  R := Item^.RcItem;
  Pressed := (Item^.ItemState and ODS_SELECTED) <> 0;
  Brush := CreateSolidBrush(TransformGroupColor(Item^.CtlID));
  FillRect(Item^.DC, R, Brush);
  DeleteObject(Brush);
  if Pressed then DrawEdge(Item^.DC, R, EDGE_SUNKEN, BF_RECT)
  else DrawEdge(Item^.DC, R, EDGE_RAISED, BF_RECT);
  FillChar(Caption, SizeOf(Caption), 0);
  GetWindowTextW(Item^.HwndItem, @Caption[0], Length(Caption));
  OldBkMode := SetBkMode(Item^.DC, TRANSPARENT);
  OldTextColor := SetTextColor(Item^.DC, RGB(0, 0, 0));
  if Pressed then OffsetRect(R, 1, 1);
  DrawTextW(Item^.DC, @Caption[0], -1, R,
    DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_END_ELLIPSIS);
  SetTextColor(Item^.DC, OldTextColor);
  SetBkMode(Item^.DC, OldBkMode);
  if (Item^.ItemState and ODS_FOCUS) <> 0 then
  begin
    R := Item^.RcItem;
    InflateRect(R, -3, -3);
    DrawFocusRect(Item^.DC, R);
  end;
end;

procedure TCsvViewer.CreateTransformSidebar;
const
  Captions: array[0..13] of PWideChar = ('Up', 'Down', '+ Add column',
    '- Remove column', '~ Rename column', 'Set all cells', 'Fill empty cells',
    'Enumerate cells', 'Load transformation (JSON)', 'Save transformation (JSON)',
    'Delimiter', 'Number format', 'Export CSV', 'Apply to grid');
  IDs: array[0..13] of Integer = (IDC_TRANSFORM_UP, IDC_TRANSFORM_DOWN,
    IDC_TRANSFORM_ADD, IDC_TRANSFORM_REMOVE, IDC_TRANSFORM_RENAME,
    IDC_TRANSFORM_CONSTANT, IDC_TRANSFORM_FILL, IDC_TRANSFORM_ENUM,
    IDC_TRANSFORM_LOAD, IDC_TRANSFORM_SAVE,
    IDC_TRANSFORM_DELIMITER, IDC_TRANSFORM_NUMBER, IDC_TRANSFORM_EXPORT, IDC_TRANSFORM_APPLY);
var
  I: Integer;
begin
  FTransformList := CreateWindowExW(WS_EX_CLIENTEDGE, WC_LISTBOXW, nil,
    WS_CHILD or WS_VSCROLL or LBS_NOTIFY, 0, 0, 0, 0, Wnd,
    IDC_TRANSFORM_LIST, HInstance, nil);
  FTransformInput := CreateWindowExW(WS_EX_CLIENTEDGE, WC_EDITW,
    nil, WS_CHILD or ES_AUTOHSCROLL,
    0, 0, 0, 0, Wnd, IDC_TRANSFORM_INPUT, HInstance, nil);
  SendMessageW(FTransformInput, $1501 {EM_SETCUEBANNER}, 0,
    LPARAM(PWideChar('Value / name / enumeration start:stop')));
  SetLength(FTransformButtons, Length(IDs));
  for I := 0 to High(IDs) do
  begin
    FTransformButtons[I] := CreateWindowExW(0, WC_BUTTONW, Captions[I],
      WS_CHILD or BS_OWNERDRAW, 0, 0, 0, 0, Wnd, IDs[I], HInstance, nil);
    SubclassChild(FTransformButtons[I]);
  end;
  SubclassChild(FTransformList);
  SubclassChild(FTransformInput);
  if FGridFont <> 0 then
  begin
    SendMessageW(FTransformList, WM_SETFONT, WPARAM(FGridFont), 0);
    SendMessageW(FTransformInput, WM_SETFONT, WPARAM(FGridFont), 0);
    for I := 0 to High(FTransformButtons) do
      SendMessageW(FTransformButtons[I], WM_SETFONT, WPARAM(FGridFont), 0);
  end;
end;

procedure TCsvViewer.RefreshTransformSidebar;
var
  I, Selection: Integer;
  S: UnicodeString;
begin
  if not IsWindow(FTransformList) then Exit;
  Selection := SendMessageW(FTransformList, LB_GETCURSEL, 0, 0);
  SendMessageW(FTransformList, LB_RESETCONTENT, 0, 0);
  for I := 0 to FTransform.TargetOrder.Count - 1 do
  begin
    S := FTransform.DisplayName(I);
    SendMessageW(FTransformList, LB_ADDSTRING, 0, LPARAM(PWideChar(S)));
  end;
  if Selection >= FTransform.TargetOrder.Count then Selection := FTransform.TargetOrder.Count - 1;
  if Selection >= 0 then SendMessageW(FTransformList, LB_SETCURSEL, Selection, 0);
  if Length(FTransformButtons) >= 14 then
  begin
    S := 'Delimiter: ' + FTransform.ExportDelimiter;
    SetWindowTextW(FTransformButtons[10], PWideChar(S));
    S := 'Number format: ' + FTransform.NumberFormat;
    SetWindowTextW(FTransformButtons[11], PWideChar(S));
    if FTransformApplied then
      SetWindowTextW(FTransformButtons[13], 'Reset grid view')
    else
      SetWindowTextW(FTransformButtons[13], 'Apply to grid');
    InvalidateRect(FTransformButtons[10], nil, True);
    InvalidateRect(FTransformButtons[11], nil, True);
    InvalidateRect(FTransformButtons[13], nil, True);
  end;
end;

procedure TCsvViewer.HandleTransformCommand(Command: Integer);
var
  Index, P, StartValue, StopValue: Integer;
  Value, FileName: UnicodeString;
begin
  if not Assigned(FTransform) then Exit;
  Index := SendMessageW(FTransformList, LB_GETCURSEL, 0, 0);
  Value := WindowText(FTransformInput);
  case Command of
    IDC_TRANSFORM_UP: begin FTransform.MoveColumn(Index, -1); Dec(Index); end;
    IDC_TRANSFORM_DOWN: begin FTransform.MoveColumn(Index, 1); Inc(Index); end;
    IDC_TRANSFORM_ADD:
      begin
        P := Pos(';', Value);
        while P > 0 do
        begin
          FTransform.AddColumn(Index + 1, Trim(Copy(Value, 1, P - 1)));
          Inc(Index);
          Delete(Value, 1, P);
          P := Pos(';', Value);
        end;
        FTransform.AddColumn(Index + 1, Trim(Value));
      end;
    IDC_TRANSFORM_REMOVE: FTransform.RemoveColumn(Index);
    IDC_TRANSFORM_RENAME: FTransform.RenameColumn(Index, Value);
    IDC_TRANSFORM_CONSTANT: FTransform.SetConstant(Index, Value);
    IDC_TRANSFORM_FILL: FTransform.SetFill(Index, Value);
    IDC_TRANSFORM_ENUM:
      begin
        P := Pos(':', Value);
        StartValue := StrToIntDef(Copy(Value, 1, P - 1), 1);
        StopValue := StrToIntDef(Copy(Value, P + 1, MaxInt),
          StartValue + FModel.VisibleCount - 1);
        FTransform.SetEnumeration(Index, StartValue, StopValue);
      end;
    IDC_TRANSFORM_LOAD:
      begin
        FileName := SelectTransformFile(Wnd, False, 'JSON configuration', 'json');
        if (FileName <> '') and not FTransform.LoadJson(FileName) then
          MessageBoxW(Wnd, 'Could not load transformation JSON.', 'csvtab',
            MB_OK or MB_ICONERROR);
      end;
    IDC_TRANSFORM_SAVE:
      begin
        FileName := SelectTransformFile(Wnd, True, 'JSON configuration', 'json');
        if (FileName <> '') and not FTransform.SaveJson(FileName) then
          MessageBoxW(Wnd, 'Could not save transformation JSON.', 'csvtab',
            MB_OK or MB_ICONERROR);
      end;
    IDC_TRANSFORM_EXPORT:
      begin
        FileName := SelectTransformFile(Wnd, True, 'CSV file', 'csv');
        if (FileName <> '') and not FTransform.ExportCsv(FileName, Doc,
          ReadSettingInt('header-row', 1) <> 0) then
          MessageBoxW(Wnd, 'Could not export transformed CSV.', 'csvtab',
            MB_OK or MB_ICONERROR);
      end;
    IDC_TRANSFORM_DELIMITER:
      case FTransform.ExportDelimiter of
        ';': FTransform.ExportDelimiter := ',';
        ',': FTransform.ExportDelimiter := #9;
      else
        FTransform.ExportDelimiter := ';';
      end;
    IDC_TRANSFORM_NUMBER:
      if FTransform.NumberFormat = 'original' then FTransform.NumberFormat := '.'
      else if FTransform.NumberFormat = '.' then FTransform.NumberFormat := ','
      else FTransform.NumberFormat := 'original';
    IDC_TRANSFORM_APPLY:
      begin
        FTransformApplied := not FTransformApplied;
        FCurrentRow := -1;
        FCurrentColumn := -1;
        BuildGrid(CalculateColumnWidths);
      end;
  else
    Exit;
  end;
  // While the preview is active, reflect every config change in the grid live.
  // Skip the commands that do not alter the previewed table (the Apply toggle
  // already rebuilds, and Save/Export/Delimiter only affect CSV export).
  if FTransformApplied and (Command <> IDC_TRANSFORM_APPLY) and
    (Command <> IDC_TRANSFORM_SAVE) and (Command <> IDC_TRANSFORM_EXPORT) and
    (Command <> IDC_TRANSFORM_DELIMITER) then
  begin
    FCurrentRow := -1;
    FCurrentColumn := -1;
    BuildGrid(CalculateColumnWidths);
  end;
  RefreshTransformSidebar;
  if (Index >= 0) and (Index < FTransform.TargetOrder.Count) then
    SendMessageW(FTransformList, LB_SETCURSEL, Index, 0);
end;

procedure TCsvViewer.CreateGridMenu;
begin
  FGridMenu := CreatePopupMenu;
  AppendMenuW(FGridMenu, MF_STRING, IDM_COPY_CELL, 'Copy cell');
  AppendMenuW(FGridMenu, MF_STRING, IDM_COPY_ROWS, 'Copy row(s) (Shift+C)');
  AppendMenuW(FGridMenu, MF_STRING, IDM_COPY_COLUMN, 'Copy column (Ctrl+C)');
  AppendMenuW(FGridMenu, MF_STRING, IDM_INSERT_ROW_BELOW, 'Insert row below');
  AppendMenuW(FGridMenu, MF_STRING, IDM_DELETE_ROW, 'Delete row(s) (Ctrl+X)');
  AppendMenuW(FGridMenu, MF_STRING, IDM_DELETE_COLUMN, 'Delete column');
  AppendMenuW(FGridMenu, MF_SEPARATOR, 0, nil);
  AppendMenuW(FGridMenu, MF_STRING, IDM_HIDE_COLUMN, 'Hide column (Ctrl+Click)');
  AppendMenuW(FGridMenu, MF_STRING, IDM_SHOW_COLUMNS, 'Show all columns (Ctrl+Space)');
  AppendMenuW(FGridMenu, MF_SEPARATOR, 0, nil);
  AppendMenuW(FGridMenu, MF_STRING, IDM_FILTER_ROW, 'Filters');
  AppendMenuW(FGridMenu, MF_STRING, IDM_HEADER_ROW, 'Header row');
  AppendMenuW(FGridMenu, MF_STRING, IDM_EDIT_MODE, 'Edit mode (Ctrl+E)');
  AppendMenuW(FGridMenu, MF_STRING, IDM_TRANSFORM_MODE, 'Transform mode (Ctrl+T)');
  AppendMenuW(FGridMenu, MF_STRING, IDM_SAVE, 'Save (Ctrl+S)');
  AppendMenuW(FGridMenu, MF_SEPARATOR, 0, nil);
  AppendMenuW(FGridMenu, MF_STRING, IDM_LINE_NUMBERS, 'Show line numbers');
  AppendMenuW(FGridMenu, MF_STRING, IDM_DARK_THEME, 'Dark theme');
end;

procedure TCsvViewer.ShowGridMenu;
var
  P: TPoint;
  Command: Integer;
  DataCol: Integer;
begin
  if FGridMenu = 0 then Exit;
  SetMenuCheck(FGridMenu, IDM_FILTER_ROW, FFilterRow);
  SetMenuCheck(FGridMenu, IDM_HEADER_ROW, ReadSettingInt('header-row', 1) <> 0);
  SetMenuCheck(FGridMenu, IDM_EDIT_MODE, FEditMode);
  SetMenuCheck(FGridMenu, IDM_TRANSFORM_MODE, FTransformMode);
  SetMenuCheck(FGridMenu, IDM_LINE_NUMBERS, FShowLineNumbers);
  SetMenuCheck(FGridMenu, IDM_DARK_THEME, ReadSettingInt('dark-theme', 0) <> 0);
  if FEditMode and not FTransformApplied and
    (FCurrentRow >= 0) and (FCurrentRow < FModel.VisibleCount) then
    EnableMenuItem(FGridMenu, IDM_INSERT_ROW_BELOW, MF_BYCOMMAND or MF_ENABLED)
  else
    EnableMenuItem(FGridMenu, IDM_INSERT_ROW_BELOW, MF_BYCOMMAND or MF_GRAYED);
  // Deleting rows is only available in edit mode and not during the preview.
  if FEditMode and not FTransformApplied then
    EnableMenuItem(FGridMenu, IDM_DELETE_ROW, MF_BYCOMMAND or MF_ENABLED)
  else
    EnableMenuItem(FGridMenu, IDM_DELETE_ROW, MF_BYCOMMAND or MF_GRAYED);
  DataCol := FCurrentColumn - NumberOffset;
  if FEditMode and not FTransformApplied and
    (DataCol >= 0) and (DataCol < Doc.ColumnCount) then
    EnableMenuItem(FGridMenu, IDM_DELETE_COLUMN, MF_BYCOMMAND or MF_ENABLED)
  else
    EnableMenuItem(FGridMenu, IDM_DELETE_COLUMN, MF_BYCOMMAND or MF_GRAYED);
  GetCursorPos(P);
  Command := LongInt(TrackPopupMenu(FGridMenu, TPM_RETURNCMD or TPM_NONOTIFY or
    TPM_RIGHTBUTTON or TPM_LEFTALIGN or TPM_TOPALIGN, P.X, P.Y, 0, Wnd, nil));
  if Command <> 0 then HandleGridCommand(Command);
end;

procedure TCsvViewer.HandleGridCommand(Command: Integer);
var
  NewModel: TCsvGridModel;
  Enabled: Boolean;
begin
  case Command of
    IDM_COPY_CELL: CopyCell;
    IDM_COPY_ROWS: CopyRows;
    IDM_COPY_COLUMN: CopyColumn;
    IDM_INSERT_ROW_BELOW: InsertRowBelowCurrent;
    IDM_DELETE_ROW: DeleteSelectedRows;
    IDM_DELETE_COLUMN: DeleteCurrentColumn;
    IDM_HIDE_COLUMN: HideColumn(FCurrentColumn);
    IDM_SHOW_COLUMNS: ShowAllColumns;
    IDM_EDIT_MODE:
      begin
        CloseCellEdit(True);
        FEditMode := not FEditMode;
        UpdateStatus;
      end;
    IDM_SAVE: SaveChanges;
    IDM_TRANSFORM_MODE:
      begin
        FTransformMode := not FTransformMode;
        RefreshTransformSidebar;
        Layout;
      end;
    IDM_FILTER_ROW:
      begin
        FFilterRow := not FFilterRow;
        WriteSettingInt('filter-row', Ord(FFilterRow));
        BuildFilterEdits;
        Layout;
      end;
    IDM_HEADER_ROW:
      begin
        Enabled := ReadSettingInt('header-row', 1) = 0;
        WriteSettingInt('header-row', Ord(Enabled));
        NewModel := TCsvGridModel.Create(Doc, Enabled);
        NewModel.CaseSensitive := ReadSettingInt('filter-case-sensitive', 0) <> 0;
        FModel.Free;
        FModel := NewModel;
        FTransform.Initialize(Doc, Enabled);
        FTransformApplied := False;
        BuildGrid(CalculateColumnWidths);
      end;
    IDM_LINE_NUMBERS:
      begin
        CloseCellEdit(True);
        FShowLineNumbers := not FShowLineNumbers;
        WriteSettingInt('show-line-numbers', Ord(FShowLineNumbers));
        FCurrentRow := -1;
        FCurrentColumn := -1;
        BuildGrid(CalculateColumnWidths);
      end;
    IDM_DARK_THEME:
      begin
        Enabled := ReadSettingInt('dark-theme', 0) = 0;
        WriteSettingInt('dark-theme', Ord(Enabled));
        ApplyTheme;
      end;
  end;
end;

procedure SetMenuCheck(Menu: HMENU; Command: UINT; Checked: Boolean);
begin
  if Checked then
    CheckMenuItem(Menu, Command, MF_BYCOMMAND or MF_CHECKED)
  else
    CheckMenuItem(Menu, Command, MF_BYCOMMAND or MF_UNCHECKED);
end;

procedure TCsvViewer.CreateStatusMenus;
begin
  FEncodingMenu := CreatePopupMenu;
  AppendMenuW(FEncodingMenu, MF_STRING, IDM_ENCODING_ANSI, 'ANSI');
  AppendMenuW(FEncodingMenu, MF_STRING, IDM_ENCODING_UTF8, 'UTF-8');
  AppendMenuW(FEncodingMenu, MF_STRING, IDM_ENCODING_UTF16LE, 'UTF-16LE');
  AppendMenuW(FEncodingMenu, MF_STRING, IDM_ENCODING_UTF16BE, 'UTF-16BE');

  FDelimiterMenu := CreatePopupMenu;
  AppendMenuW(FDelimiterMenu, MF_STRING, IDM_DELIMITER_AUTO, 'Auto');
  AppendMenuW(FDelimiterMenu, MF_STRING, IDM_DELIMITER_COMMA, ',');
  AppendMenuW(FDelimiterMenu, MF_STRING, IDM_DELIMITER_SEMICOLON, ';');
  AppendMenuW(FDelimiterMenu, MF_STRING, IDM_DELIMITER_VBAR, '|');
  AppendMenuW(FDelimiterMenu, MF_STRING, IDM_DELIMITER_TAB, 'TAB');
  AppendMenuW(FDelimiterMenu, MF_STRING, IDM_DELIMITER_COLON, ':');

  FCommentMenu := CreatePopupMenu;
  AppendMenuW(FCommentMenu, MF_STRING, IDM_COMMENTS_AUTO, 'Auto');
  AppendMenuW(FCommentMenu, MF_STRING, IDM_COMMENTS_PARSE, 'Parse normally');
  AppendMenuW(FCommentMenu, MF_STRING, IDM_COMMENTS_NOPARSE, 'Do not parse');
  AppendMenuW(FCommentMenu, MF_STRING, IDM_COMMENTS_HIDE, 'Hide');
end;

function TCsvViewer.ReloadDocument: Boolean;
var
  NewDoc: TCsvDocument;
  NewModel: TCsvGridModel;
  LineNumberWidth: Integer;
  ReloadDelimiter: WideChar;
begin
  Result := False;
  if not ConfirmChanges('reloading') then Exit;
  if IsWindow(Wnd) then KillTimer(Wnd, IDT_VALUE_DECODE);
  LineNumberWidth := 0;
  if FShowLineNumbers and IsWindow(FGrid) then
    LineNumberWidth := ListView_GetColumnWidth(FGrid, 0);
  NewDoc := nil;
  NewModel := nil;
  if FDelimiterAuto then ReloadDelimiter := #0
  else ReloadDelimiter := FDelimiterChoice;
  if not LoadCsvFileAs(FileName, ReadSettingInt('max-file-size', 10000000),
    ReloadDelimiter, FSkipComments, FEncodingChoice, NewDoc,
    ReadSettingInt('trim-values', 1) <> 0,
    ReadSettingInt('max-column-samples', 1000)) then Exit;
  try
    NewModel := TCsvGridModel.Create(NewDoc,
      ReadSettingInt('header-row', 1) <> 0);
    NewModel.CaseSensitive := ReadSettingInt('filter-case-sensitive', 0) <> 0;
  except
    NewModel.Free;
    NewDoc.Free;
    Exit;
  end;
  FModel.Free;
  Doc.Free;
  FModel := NewModel;
  Doc := NewDoc;
  FDirty := False;
  FEncodingChoice := Doc.Encoding.Name;
  if not FDelimiterAuto then FDelimiterChoice := Doc.Delimiter;
  FCurrentRow := -1;
  FCurrentColumn := -1;
  FSearchText := '';
  FSearchFlags := 0;
  FSearchRow := 0;
  FSearchColumn := 0;
  FSearchCellPos := 1;
  FTransform.Initialize(Doc, ReadSettingInt('header-row', 1) <> 0);
  FTransformApplied := False;
  BuildGrid(CalculateColumnWidths);
  if FShowLineNumbers and (LineNumberWidth > 0) then
    SendMessageW(FGrid, LVM_SETCOLUMNWIDTH, 0, LineNumberWidth);
  LayoutFilterEdits;
  InvalidateRect(FGrid, nil, True);
  UpdateStatus;
  StartValueDecodeTimer;
  Result := True;
end;

procedure TCsvViewer.HandleStatusCommand(Command: Integer);
var
  OldEncoding: UnicodeString;
  OldDelimiter: WideChar;
  OldDelimiterAuto: Boolean;
  OldSkipComments: Integer;
  OldCommentsAuto: Boolean;
begin
  OldEncoding := FEncodingChoice;
  OldDelimiter := FDelimiterChoice;
  OldDelimiterAuto := FDelimiterAuto;
  OldSkipComments := FSkipComments;
  OldCommentsAuto := FCommentsAuto;
  case Command of
    IDM_ENCODING_ANSI: FEncodingChoice := 'ANSI';
    IDM_ENCODING_UTF8: FEncodingChoice := 'UTF-8';
    IDM_ENCODING_UTF16LE: FEncodingChoice := 'UTF-16LE';
    IDM_ENCODING_UTF16BE: FEncodingChoice := 'UTF-16BE';
    IDM_DELIMITER_AUTO:
      begin
        FDelimiterAuto := True;
        FDelimiterChoice := #0;
      end;
    IDM_DELIMITER_COMMA:
      begin
        FDelimiterAuto := False;
        FDelimiterChoice := ',';
      end;
    IDM_DELIMITER_SEMICOLON:
      begin
        FDelimiterAuto := False;
        FDelimiterChoice := ';';
      end;
    IDM_DELIMITER_VBAR:
      begin
        FDelimiterAuto := False;
        FDelimiterChoice := '|';
      end;
    IDM_DELIMITER_TAB:
      begin
        FDelimiterAuto := False;
        FDelimiterChoice := #9;
      end;
    IDM_DELIMITER_COLON:
      begin
        FDelimiterAuto := False;
        FDelimiterChoice := ':';
      end;
    IDM_COMMENTS_AUTO:
      begin
        FCommentsAuto := True;
        FSkipComments := 3;
      end;
    IDM_COMMENTS_PARSE:
      begin
        FCommentsAuto := False;
        FSkipComments := 0;
      end;
    IDM_COMMENTS_NOPARSE:
      begin
        FCommentsAuto := False;
        FSkipComments := 1;
      end;
    IDM_COMMENTS_HIDE:
      begin
        FCommentsAuto := False;
        FSkipComments := 2;
      end;
  else
    Exit;
  end;
  if not ReloadDocument then
  begin
    FEncodingChoice := OldEncoding;
    FDelimiterChoice := OldDelimiter;
    FDelimiterAuto := OldDelimiterAuto;
    FSkipComments := OldSkipComments;
    FCommentsAuto := OldCommentsAuto;
    ShowCsvLoadError(Wnd, 'The file could not be reloaded.');
  end
  else if (Command = IDM_COMMENTS_AUTO) or (Command = IDM_COMMENTS_PARSE) or
    (Command = IDM_COMMENTS_NOPARSE) or (Command = IDM_COMMENTS_HIDE) then
  begin
    LayoutFilterEdits;
  end;
end;

procedure TCsvViewer.ShowStatusMenu(Part: Integer);
var
  Menu: HMENU;
  R: TRect;
  P: TPoint;
  Command: Integer;
begin
  Menu := 0;
  case Part of
    0:
      begin
        Menu := FEncodingMenu;
        SetMenuCheck(Menu, IDM_ENCODING_ANSI, SameText(Doc.Encoding.Name, 'ANSI'));
        SetMenuCheck(Menu, IDM_ENCODING_UTF8, SameText(Doc.Encoding.Name, 'UTF-8'));
        SetMenuCheck(Menu, IDM_ENCODING_UTF16LE, SameText(Doc.Encoding.Name, 'UTF-16LE'));
        SetMenuCheck(Menu, IDM_ENCODING_UTF16BE, SameText(Doc.Encoding.Name, 'UTF-16BE'));
      end;
    1:
      begin
        Menu := FDelimiterMenu;
        SetMenuCheck(Menu, IDM_DELIMITER_AUTO, FDelimiterAuto);
        SetMenuCheck(Menu, IDM_DELIMITER_COMMA,
          not FDelimiterAuto and (Doc.Delimiter = ','));
        SetMenuCheck(Menu, IDM_DELIMITER_SEMICOLON,
          not FDelimiterAuto and (Doc.Delimiter = ';'));
        SetMenuCheck(Menu, IDM_DELIMITER_VBAR,
          not FDelimiterAuto and (Doc.Delimiter = '|'));
        SetMenuCheck(Menu, IDM_DELIMITER_TAB,
          not FDelimiterAuto and (Doc.Delimiter = #9));
        SetMenuCheck(Menu, IDM_DELIMITER_COLON,
          not FDelimiterAuto and (Doc.Delimiter = ':'));
      end;
    2:
      begin
        Menu := FCommentMenu;
        SetMenuCheck(Menu, IDM_COMMENTS_AUTO, FCommentsAuto);
        SetMenuCheck(Menu, IDM_COMMENTS_PARSE,
          not FCommentsAuto and (FSkipComments = 0));
        SetMenuCheck(Menu, IDM_COMMENTS_NOPARSE,
          not FCommentsAuto and (FSkipComments = 1));
        SetMenuCheck(Menu, IDM_COMMENTS_HIDE,
          not FCommentsAuto and (FSkipComments = 2));
      end;
  end;
  if Menu = 0 then Exit;
  SendMessageW(FStatus, SB_GETRECT, Part, LPARAM(@R));
  P.X := R.Left;
  P.Y := R.Top;
  ClientToScreen(FStatus, P);
  Command := LongInt(TrackPopupMenu(Menu, TPM_RETURNCMD or TPM_NONOTIFY or
    TPM_LEFTALIGN or TPM_BOTTOMALIGN, P.X, P.Y, 0, Wnd, nil));
  if Command <> 0 then HandleStatusCommand(Command);
end;

function MeasureTextWidth(DC: HDC; const S: UnicodeString): Integer;
var
  Size: TSize;
begin
  Result := 0;
  if (S = '') or not GetTextExtentPoint32W(DC, PWideChar(S), Length(S), Size) then
    Exit;
  Result := Size.cx;
end;

procedure TCsvViewer.UpdateDecimalAnchors;
var
  DC: HDC;
  OldFont: HGDIOBJ;
  Column, Row, Width, SampleNo, Samples: Integer;
  S, IntegerPart, FractionPart: UnicodeString;
  Separator: WideChar;
begin
  SetLength(FDecimalAnchors, ActiveColumnCount);
  SetLength(FDecimalColumns, ActiveColumnCount);
  SetLength(FNumericColumns, ActiveColumnCount);
  if Length(FDecimalAnchors) > 0 then
  begin
    FillChar(FDecimalAnchors[0], Length(FDecimalAnchors) * SizeOf(Integer), 0);
    FillChar(FDecimalColumns[0], Length(FDecimalColumns) * SizeOf(Boolean), 0);
    FillChar(FNumericColumns[0], Length(FNumericColumns) * SizeOf(Boolean), 0);
  end;
  if not FDecimalAlign or not IsWindow(FGrid) then Exit;
  Samples := SampleCount(FModel.VisibleCount,
    ReadSettingInt('max-column-samples', 1000));
  if Samples <= 0 then Exit;
  DC := GetDC(FGrid);
  if DC = 0 then Exit;
  OldFont := 0;
  if FGridFont <> 0 then OldFont := SelectObject(DC, FGridFont);
  try
    for Column := NumberOffset to ActiveColumnCount - 1 do
      for SampleNo := 0 to Samples - 1 do
      begin
        Row := SamplePosition(SampleNo, Samples, FModel.VisibleCount);
        S := ActiveCellText(Row, Column);
        if SplitDecimalText(S, IntegerPart, FractionPart, Separator) then
        begin
          FNumericColumns[Column] := True;
          FDecimalColumns[Column] := True;
          Width := MeasureTextWidth(DC, IntegerPart);
          if Width > FDecimalAnchors[Column] then
            FDecimalAnchors[Column] := Width;
        end;
        if IsIntegerText(S) then
        begin
          FNumericColumns[Column] := True;
          FDecimalColumns[Column] := True;
          Width := MeasureTextWidth(DC, Trim(S));
          if Width > FDecimalAnchors[Column] then
            FDecimalAnchors[Column] := Width;
        end;
      end;
  finally
    if OldFont <> 0 then SelectObject(DC, OldFont);
    ReleaseDC(FGrid, DC);
  end;
end;

function TCsvViewer.CalculateColumnWidths: TIntegerArray;
const
  CELL_PADDING = 24;
  LINE_NUMBER_PADDING = 12;
var
  DC: HDC;
  OldFont: HGDIOBJ;
  Column, DataCol, SampleNo, Samples, Row, Width, MaxWidth, TextWidth: Integer;
begin
  SetLength(Result, ActiveColumnCount);
  for Column := 0 to High(Result) do Result[Column] := 140;
  if not IsWindow(FGrid) then Exit;
  DC := GetDC(FGrid);
  if DC = 0 then Exit;
  OldFont := 0;
  if FGridFont <> 0 then OldFont := SelectObject(DC, FGridFont);
  try
    Samples := SampleCount(FModel.VisibleCount,
      ReadSettingInt('max-column-samples', 1000));
    MaxWidth := ReadSettingInt('max-column-width', 300);
    for Column := 0 to ActiveColumnCount - 1 do
    begin
      if FShowLineNumbers and (Column = 0) then
      begin
        Width := MeasureTextWidth(DC, '#') + LINE_NUMBER_PADDING;
        TextWidth := MeasureTextWidth(DC,
          UnicodeString(IntToStr(Max(1, FModel.VisibleCount)))) +
          LINE_NUMBER_PADDING;
        if TextWidth > Width then Width := TextWidth;
        Result[Column] := Width;
        Continue;
      end;
      DataCol := Column - NumberOffset;
      if (DataCol >= 0) and (DataCol < Length(FHiddenColumns)) and
        FHiddenColumns[DataCol] then
      begin
        Result[Column] := 0;
        Continue;
      end;
      Width := MeasureTextWidth(DC, ActiveHeaderText(Column)) + CELL_PADDING;
      for SampleNo := 0 to Samples - 1 do
      begin
        Row := SamplePosition(SampleNo, Samples, FModel.VisibleCount);
        TextWidth := MeasureTextWidth(DC, ActiveCellText(Row, Column)) +
          CELL_PADDING;
        if TextWidth > Width then Width := TextWidth;
      end;
      if Width < CELL_PADDING then Width := CELL_PADDING;
      if (ActiveColumnCount > 1) and (MaxWidth > 0) and (Width > MaxWidth) then
        Width := MaxWidth;
      Result[Column] := Width;
    end;
  finally
    if OldFont <> 0 then SelectObject(DC, OldFont);
    ReleaseDC(FGrid, DC);
  end;
end;

procedure TCsvViewer.AutoSizeColumns;
var
  Widths: TIntegerArray;
  Column: Integer;
begin
  Widths := CalculateColumnWidths;
  for Column := 0 to High(Widths) do
    SendMessageW(FGrid, LVM_SETCOLUMNWIDTH, Column, Widths[Column]);
end;

procedure TCsvViewer.ApplyFilter(Column: Integer);
var
  TextLength, DataCol: Integer;
  Text: UnicodeString;
begin
  if (Column < 0) or (Column >= Length(FFilterEdits)) or
    not IsWindow(FFilterEdits[Column]) then Exit;
  DataCol := Column - NumberOffset;
  if DataCol < 0 then Exit;
  TextLength := GetWindowTextLengthW(FFilterEdits[Column]);
  SetLength(Text, TextLength);
  if TextLength > 0 then
    GetWindowTextW(FFilterEdits[Column], PWideChar(Text), TextLength + 1);
  FModel.SetFilter(DataCol, Text);
  FSearchText := '';
  FCurrentRow := -1;
  FCurrentColumn := -1;
  SendMessageW(FGrid, LVM_SETITEMCOUNT, FModel.VisibleCount, 0);
  InvalidateRect(FGrid, nil, True);
  LayoutFilterEdits;
  UpdateStatus;
end;

procedure TCsvViewer.LayoutFilterEdits;
var
  Column, Flags, TopPos, Width: Integer;
  GridR, R: TRect;
  Positions: HDWP;
  Visible: Boolean;
begin
  if not IsWindow(FGrid) or not IsWindow(FHeader) then Exit;
  GetClientRect(FGrid, GridR);
  MapWindowPoints(FGrid, Wnd, @GridR, 2);
  TopPos := GridR.Top - 24;
  Visible := FFilterRow and not FTransformApplied;
  Positions := BeginDeferWindowPos(Length(FFilterEdits));
  for Column := 0 to High(FFilterEdits) do
  begin
    if IsWindow(FFilterEdits[Column]) then
    begin
      FillChar(R, SizeOf(R), 0);
      if Header_GetItemRect(FHeader, Column, LPARAM(@R)) then
      begin
        MapWindowPoints(FHeader, Wnd, @R, 2);
        if R.Left < GridR.Left then R.Left := GridR.Left;
        if R.Right > GridR.Right then R.Right := GridR.Right;
      end
      else
      begin
        R.Left := GridR.Left;
        R.Right := GridR.Left;
      end;
      Width := Max(0, R.Right - R.Left);
      Flags := SWP_NOACTIVATE or SWP_NOZORDER;
      if Visible and (Width > 0) then Flags := Flags or SWP_SHOWWINDOW
      else Flags := Flags or SWP_HIDEWINDOW;
      if Positions <> 0 then
        Positions := DeferWindowPos(Positions, FFilterEdits[Column], 0,
          R.Left, TopPos, Width, 24, Flags)
      else
        SetWindowPos(FFilterEdits[Column], 0, R.Left, TopPos, Width, 24,
          Flags);
    end;
  end;
  if Positions <> 0 then EndDeferWindowPos(Positions);
end;

procedure TCsvViewer.BuildFilterEdits;
var
  Column, AlignStyle, ColCount: Integer;
begin
  ColCount := ActiveColumnCount;
  if Length(FHiddenColumns) <> ColCount - NumberOffset then
    SetLength(FHiddenColumns, ColCount - NumberOffset);
  for Column := 0 to High(FFilterEdits) do
    if IsWindow(FFilterEdits[Column]) then DestroyWindow(FFilterEdits[Column]);
  SetLength(FFilterEdits, ColCount);
  if not IsWindow(FHeader) then Exit;

  if FTransformApplied then Exit;

  case ReadSettingInt('filter-align', 0) of
    -1: AlignStyle := ES_LEFT;
    1: AlignStyle := ES_RIGHT;
  else
    AlignStyle := ES_CENTER;
  end;
  for Column := 0 to ColCount - 1 do
  begin
    // No filter under the line-number column.
    if FShowLineNumbers and (Column = 0) then
    begin
      FFilterEdits[Column] := 0;
      Continue;
    end;
    FFilterEdits[Column] := CreateWindowExW(0, WC_EDITW, nil,
      WS_CHILD or WS_TABSTOP or WS_BORDER or ES_AUTOHSCROLL or AlignStyle,
      0, 0, 0, 0, Wnd, IDC_FILTER_BASE + Column, HInstance, nil);
    if FGridFont <> 0 then
      SendMessageW(FFilterEdits[Column], WM_SETFONT, WPARAM(FGridFont), 0);
    SubclassChild(FFilterEdits[Column]);
  end;
  LayoutFilterEdits;
end;

function TCsvViewer.NumberOffset: Integer;
begin
  // 1 when the line-number column occupies grid column 0, else 0. Data columns
  // are shifted right by this amount; callers map grid <-> data columns with it.
  if FShowLineNumbers then Result := 1 else Result := 0;
end;

function TCsvViewer.ActiveColumnCount: Integer;
begin
  if FTransformApplied and Assigned(FTransform) then
    Result := FTransform.TransformedColumnCount
  else
    Result := Doc.ColumnCount;
  Result := Result + NumberOffset;
end;

function TCsvViewer.ActiveHeaderText(Col: Integer): UnicodeString;
begin
  if FShowLineNumbers then
  begin
    if Col = 0 then Exit('#');
    Dec(Col);
  end;
  if FTransformApplied and Assigned(FTransform) then
    Result := FTransform.TransformedHeader(Col)
  else
    Result := FModel.HeaderText(Col);
end;

function TCsvViewer.ActiveCellText(VisibleRow, Col: Integer): UnicodeString;
var
  SourceRow, DataStart: Integer;
begin
  if FShowLineNumbers then
  begin
    if Col = 0 then Exit(UnicodeString(IntToStr(VisibleRow + 1)));
    Dec(Col);
  end;
  if FTransformApplied and Assigned(FTransform) then
  begin
    SourceRow := FModel.SourceRowAt(VisibleRow);
    DataStart := Ord(ReadSettingInt('header-row', 1) <> 0);
    Result := FTransform.TransformedCellValue(Col, SourceRow, DataStart, Doc);
  end
  else
    Result := FModel.CellText(VisibleRow, Col);
end;

procedure TCsvViewer.BuildGrid(const Widths: TIntegerArray);
var
  Column: Integer;
  LVC: TLVColumnW;
  Header: UnicodeString;
begin
  FSearchText := '';
  for Column := 0 to High(FFilterEdits) do
    if IsWindow(FFilterEdits[Column]) then DestroyWindow(FFilterEdits[Column]);
  SetLength(FFilterEdits, 0);
  while Header_GetItemCount(FHeader) > 0 do
    SendMessageW(FGrid, LVM_DELETECOLUMN, 0, 0);
  for Column := 0 to ActiveColumnCount - 1 do
  begin
    Header := ActiveHeaderText(Column);
    FillChar(LVC, SizeOf(LVC), 0);
    LVC.mask := LVCF_TEXT or LVCF_WIDTH or LVCF_FMT;
    LVC.fmt := LVCFMT_LEFT;
    if (Column >= 0) and (Column < Length(Widths)) then
      LVC.cx := Widths[Column]
    else
      LVC.cx := 140;
    LVC.pszText := PWideChar(Header);
    SendMessageW(FGrid, LVM_INSERTCOLUMNW, Column, LPARAM(@LVC));
  end;
  BuildFilterEdits;
  UpdateHeaderSortIndicators;
  SendMessageW(FGrid, LVM_SETITEMCOUNT, FModel.VisibleCount, 0);
  UpdateDecimalAnchors;
  FInitialAutoSizeDone := True;
  UpdateStatus;
end;

procedure TCsvViewer.LoadInitialDocument;
var
  DelimiterText: UnicodeString;
  Delimiter: WideChar;
begin
  if FLoaded then Exit;
  DelimiterText := ReadSetting('default-column-delimiter', '');
  FDelimiterAuto := DelimiterText = '';
  if FDelimiterAuto then Delimiter := #0 else Delimiter := DelimiterText[1];
  if not LoadCsvFile(FileName, ReadSettingInt('max-file-size', 10000000),
    Delimiter, FSkipComments, Doc, ReadSettingInt('trim-values', 1) <> 0,
    ReadSettingInt('max-column-samples', 1000)) then
  begin
    ShowCsvLoadError(Wnd, 'The file could not be loaded.');
    DestroyWindow(Wnd);
    Exit;
  end;
  FEncodingChoice := Doc.Encoding.Name;
  if FDelimiterAuto then FDelimiterChoice := #0
  else FDelimiterChoice := Doc.Delimiter;
  try
    FModel := TCsvGridModel.Create(Doc, ReadSettingInt('header-row', 1) <> 0);
    FModel.CaseSensitive := ReadSettingInt('filter-case-sensitive', 0) <> 0;
    FTransform.Initialize(Doc, ReadSettingInt('header-row', 1) <> 0);
  except
    FModel.Free;
    FModel := nil;
    Doc.Free;
    Doc := nil;
    ShowCsvLoadError(Wnd, 'The file could not be loaded.');
    DestroyWindow(Wnd);
    Exit;
  end;
  FLoaded := True;
  if FTransformMode then RefreshTransformSidebar;
  BuildGrid(CalculateColumnWidths);
  Layout;
  StartValueDecodeTimer;
  PostMessageW(Wnd, WM_CSV_SETFOCUS, 0, 0);
end;

procedure TCsvViewer.StartValueDecodeTimer;
begin
  if not IsWindow(Wnd) then Exit;
  KillTimer(Wnd, IDT_VALUE_DECODE);
  if Assigned(Doc) and Doc.HasPendingValues then
    SetTimer(Wnd, IDT_VALUE_DECODE, 15, nil);
end;

procedure TCsvViewer.DecodeValueBatch;
begin
  if not Assigned(Doc) then
  begin
    KillTimer(Wnd, IDT_VALUE_DECODE);
    Exit;
  end;
  Doc.DecodePendingValues(2000);
  if not Doc.HasPendingValues then
    KillTimer(Wnd, IDT_VALUE_DECODE);
end;

procedure TCsvViewer.SortColumn(Column: Integer);
var
  Direction, DataCol, SavedCurrentColumn, SavedCurrentSource, SavedTopIndex,
    SavedHorz, NewCurrentRow, TargetTop, CurrentTop, RowHeight, Dx,
    Dy: Integer;
  R: TRect;

  procedure SetSortRedraw(Enabled: Boolean);
  var
    I: Integer;
    Flag: WPARAM;
  begin
    Flag := Ord(Enabled);
    SendMessageW(FGrid, WM_SETREDRAW, Flag, 0);
    if IsWindow(FHeader) then SendMessageW(FHeader, WM_SETREDRAW, Flag, 0);
    for I := 0 to High(FFilterEdits) do
      if IsWindow(FFilterEdits[I]) then
        SendMessageW(FFilterEdits[I], WM_SETREDRAW, Flag, 0);
  end;

  procedure RedrawSortedView;
  var
    I: Integer;
  begin
    RedrawWindow(FGrid, nil, 0,
      RDW_INVALIDATE or RDW_FRAME or RDW_ALLCHILDREN);
    if IsWindow(FHeader) then
      RedrawWindow(FHeader, nil, 0, RDW_INVALIDATE or RDW_FRAME);
    for I := 0 to High(FFilterEdits) do
      if IsWindow(FFilterEdits[I]) then
        RedrawWindow(FFilterEdits[I], nil, 0, RDW_INVALIDATE or RDW_FRAME);
  end;

  function VisibleIndexOfSourceRow(SourceRow: Integer): Integer;
  var
    Row: Integer;
  begin
    Result := -1;
    if SourceRow < 0 then Exit;
    for Row := 0 to FModel.VisibleCount - 1 do
      if FModel.SourceRowAt(Row) = SourceRow then Exit(Row);
  end;

begin
  if not FLoaded then Exit;
  if FTransformApplied then Exit;
  DataCol := Column - NumberOffset;
  if DataCol < 0 then Exit; // clicking the line-number header does nothing
  SavedCurrentColumn := FCurrentColumn;
  if SavedCurrentColumn < 0 then SavedCurrentColumn := Column;
  SavedCurrentSource := -1;
  if (FCurrentRow >= 0) and (FCurrentRow < FModel.VisibleCount) then
    SavedCurrentSource := FModel.SourceRowAt(FCurrentRow);
  SavedTopIndex := SendMessageW(FGrid, LVM_GETTOPINDEX, 0, 0);
  if SavedTopIndex < 0 then SavedTopIndex := 0;
  SavedHorz := GetScrollPos(FGrid, SB_HORZ);
  if FModel.SortColumn <> DataCol then Direction := 1
  else if FModel.SortDirection > 0 then Direction := -1
  else if FModel.SortDirection < 0 then Direction := 0
  else Direction := 1;
  SetSortRedraw(False);
  try
    FModel.SetSort(DataCol, Direction);
    FSearchText := '';
    UpdateHeaderSortIndicators;
    SendMessageW(FGrid, LVM_SETITEMCOUNT, FModel.VisibleCount,
      LVSICF_NOSCROLL_FLAG);
    NewCurrentRow := VisibleIndexOfSourceRow(SavedCurrentSource);
    FCurrentRow := NewCurrentRow;
    FCurrentColumn := SavedCurrentColumn;
    if FCurrentColumn >= ActiveColumnCount then FCurrentColumn := ActiveColumnCount - 1;
    if FCurrentColumn < 0 then FCurrentColumn := -1;
    if NewCurrentRow >= 0 then
    begin
      ListView_SetItemState(FGrid, -1, 0, LVIS_SELECTED or LVIS_FOCUSED);
      ListView_SetItemState(FGrid, NewCurrentRow, LVIS_SELECTED or LVIS_FOCUSED,
        LVIS_SELECTED or LVIS_FOCUSED);
    end;
    if FModel.VisibleCount > 0 then
    begin
      TargetTop := SavedTopIndex;
      if TargetTop >= FModel.VisibleCount then TargetTop := FModel.VisibleCount - 1;
      CurrentTop := SendMessageW(FGrid, LVM_GETTOPINDEX, 0, 0);
      FillChar(R, SizeOf(R), 0);
      R.Left := LVIR_BOUNDS;
      if SendMessageW(FGrid, LVM_GETITEMRECT, 0, LPARAM(@R)) <> 0 then
      begin
        RowHeight := R.Bottom - R.Top;
        Dy := (TargetTop - CurrentTop) * RowHeight;
        if Dy <> 0 then SendMessageW(FGrid, LVM_SCROLL, 0, Dy);
      end;
    end;
    Dx := SavedHorz - GetScrollPos(FGrid, SB_HORZ);
    if Dx <> 0 then SendMessageW(FGrid, LVM_SCROLL, Dx, 0);
    LayoutFilterEdits;
  finally
    SetSortRedraw(True);
  end;
  RedrawSortedView;
  UpdateStatus;
end;

function IsWordChar(C: WideChar): Boolean;
begin
  Result := (C = '_') or (C >= '0') and (C <= '9') or
    (C >= 'A') and (C <= 'Z') or (C >= 'a') and (C <= 'z') or (Ord(C) > 127);
end;

function FindText(const Value, SearchText: UnicodeString; StartPos: Integer;
  MatchCase, WholeWords: Boolean): Integer;
var
  Haystack, Needle: UnicodeString;
  P: Integer;
begin
  Result := 0;
  if SearchText = '' then Exit;
  Haystack := Value;
  Needle := SearchText;
  if not MatchCase then
  begin
    Haystack := UnicodeLowerCase(Haystack);
    Needle := UnicodeLowerCase(Needle);
  end;
  if StartPos < 1 then StartPos := 1;
  while StartPos <= Length(Haystack) do
  begin
    P := Pos(Needle, Copy(Haystack, StartPos, MaxInt));
    if P = 0 then Exit;
    P := P + StartPos - 1;
    if not WholeWords or
      ((P = 1) or not IsWordChar(Haystack[P - 1])) and
      ((P + Length(Needle) > Length(Haystack)) or
       not IsWordChar(Haystack[P + Length(Needle)])) then Exit(P);
    StartPos := P + 1;
  end;
end;

function FindTextBackwards(const Value, SearchText: UnicodeString; BeforePos: Integer;
  MatchCase, WholeWords: Boolean): Integer;
var
  Position, NextPosition: Integer;
begin
  Result := 0;
  if BeforePos <= 0 then BeforePos := Length(Value) + 1;
  Position := FindText(Value, SearchText, 1, MatchCase, WholeWords);
  while (Position > 0) and (Position < BeforePos) do
  begin
    Result := Position;
    NextPosition := FindText(Value, SearchText, Position + 1, MatchCase, WholeWords);
    if NextPosition <= Position then Break;
    Position := NextPosition;
  end;
end;

function TCsvViewer.Search(const SearchText: UnicodeString;
  SearchFlags: Integer): Integer;
var
  Row, Column, Position, StartPosition, RelevantFlags, ColumnCount: Integer;
  Backwards, WasBackwards, DirectionChanged, ResetSearch, MatchCase,
    WholeWords: Boolean;
begin
  Result := 0;
  if (not FLoaded) or not Assigned(FModel) then Exit;
  ColumnCount := ActiveColumnCount;
  if (SearchText = '') or (FModel.VisibleCount = 0) or (ColumnCount = 0) then Exit;
  Backwards := (SearchFlags and lcs_backwards) <> 0;
  WasBackwards := (FSearchFlags and lcs_backwards) <> 0;
  DirectionChanged := (FSearchText = SearchText) and (Backwards <> WasBackwards);
  RelevantFlags := SearchFlags and (lcs_matchcase or lcs_wholewords);
  ResetSearch := (FSearchText <> SearchText) or
    ((FSearchFlags and (lcs_matchcase or lcs_wholewords)) <> RelevantFlags) or
    (((SearchFlags and lcs_findfirst) <> 0) and not DirectionChanged);
  MatchCase := (SearchFlags and lcs_matchcase) <> 0;
  WholeWords := (SearchFlags and lcs_wholewords) <> 0;
  FSearchText := SearchText;
  FSearchFlags := RelevantFlags;
  if Backwards then FSearchFlags := FSearchFlags or lcs_backwards;
  if ResetSearch then
  begin
    if Backwards then
    begin
      FSearchRow := FModel.VisibleCount - 1;
      FSearchColumn := ColumnCount - 1;
      FSearchCellPos := MaxInt;
    end
    else
    begin
      FSearchRow := 0;
      FSearchColumn := 0;
      FSearchCellPos := 1;
    end;
  end;
  if DirectionChanged and not ResetSearch then
  begin
    if Backwards then Dec(FSearchCellPos, Length(SearchText))
    else Inc(FSearchCellPos, Length(SearchText));
  end;
  Row := FSearchRow;
  Column := FSearchColumn;
  while (Row >= 0) and (Row < FModel.VisibleCount) do
  begin
    while (Column >= 0) and (Column < ColumnCount) do
    begin
      StartPosition := FSearchCellPos;
      if FShowLineNumbers and (Column = 0) then
        Position := 0 // do not search inside the line-number column
      else if Backwards then
        Position := FindTextBackwards(ActiveCellText(Row, Column), SearchText,
          StartPosition, MatchCase, WholeWords)
      else
        Position := FindText(ActiveCellText(Row, Column), SearchText,
          StartPosition, MatchCase, WholeWords);
      if Position > 0 then
      begin
        FSearchRow := Row;
        FSearchColumn := Column;
        if Backwards then FSearchCellPos := Position
        else FSearchCellPos := Position + Length(SearchText);
        FCurrentRow := Row;
        FCurrentColumn := Column;
        ListView_SetItemState(FGrid, -1, 0, LVIS_SELECTED or LVIS_FOCUSED);
        ListView_SetItemState(FGrid, Row, LVIS_SELECTED or LVIS_FOCUSED,
          LVIS_SELECTED or LVIS_FOCUSED);
        ListView_EnsureVisible(FGrid, Row, False);
        UpdateStatus;
        SetFocus(FGrid);
        Exit(1);
      end;
      if Backwards then
      begin
        Dec(Column);
        FSearchCellPos := MaxInt;
      end
      else
      begin
        Inc(Column);
        FSearchCellPos := 1;
      end;
    end;
    if Backwards then
    begin
      Dec(Row);
      Column := ColumnCount - 1;
      FSearchCellPos := MaxInt;
    end
    else
    begin
      Inc(Row);
      Column := 0;
      FSearchCellPos := 1;
    end;
  end;
  MessageBeep(0);
end;

function ViewerWndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM;
  LParam: LPARAM): LRESULT; stdcall;
var
  V: TCsvViewer;
  N: PNMHDR;
  Item: PLVDispInfoW;
  Row, Column: Integer;
  P: TPoint;
  HeaderHit: THDHitTestInfo;
  S: UnicodeString;
begin
  V := ViewerFromWnd(Wnd);
  case Msg of
    WM_CTLCOLORSTATIC:
      if Assigned(V) and (HWND(LParam) = V.FLoading) then
      begin
        SetTextColor(HDC(WParam), V.FTextColor);
        SetBkColor(HDC(WParam), V.FBackColor);
        Exit(LRESULT(V.FLoadingBrush));
      end;
    WM_CTLCOLOREDIT:
      if Assigned(V) then
      begin
        SetTextColor(HDC(WParam), V.FFilterTextColor);
        SetBkColor(HDC(WParam), V.FFilterBackColor);
        Exit(LRESULT(V.FFilterBrush));
      end;
    WM_COMMAND:
      if Assigned(V) and V.FLoaded and (HiWord(WParam) = EN_CHANGE) and
        (LoWord(WParam) >= IDC_FILTER_BASE) and
        (LoWord(WParam) < IDC_FILTER_BASE + Length(V.FFilterEdits)) then
      begin
        V.ApplyFilter(LoWord(WParam) - IDC_FILTER_BASE);
        Exit(0);
      end
      else if Assigned(V) and V.FLoaded and
        (((LoWord(WParam) >= IDM_ENCODING_ANSI) and
          (LoWord(WParam) <= IDM_ENCODING_UTF16BE)) or
         ((LoWord(WParam) >= IDM_DELIMITER_COMMA) and
          (LoWord(WParam) <= IDM_DELIMITER_AUTO)) or
         ((LoWord(WParam) >= IDM_COMMENTS_PARSE) and
          (LoWord(WParam) <= IDM_COMMENTS_AUTO))) then
      begin
        V.HandleStatusCommand(LoWord(WParam));
        Exit(0);
      end
      else if Assigned(V) and V.FLoaded and (LoWord(WParam) = IDM_TRANSFORM_MODE) then
      begin
        V.HandleGridCommand(IDM_TRANSFORM_MODE);
        Exit(0);
      end
      else if Assigned(V) and V.FLoaded and (LoWord(WParam) >= IDC_TRANSFORM_UP) and
        (LoWord(WParam) <= IDC_TRANSFORM_APPLY) then
      begin
        V.HandleTransformCommand(LoWord(WParam));
        Exit(0);
      end;
    WM_CSV_SETFOCUS:
      if Assigned(V) and V.FTakeInitialFocus and IsWindow(V.FGrid) then
      begin
        SetFocus(V.FGrid);
        Exit(0);
      end;
    WM_TIMER:
      if Assigned(V) and (WParam = IDT_INITIAL_LOAD) then
      begin
        KillTimer(Wnd, IDT_INITIAL_LOAD);
        V.LoadInitialDocument;
        Exit(0);
      end
      else if Assigned(V) and (WParam = IDT_VALUE_DECODE) then
      begin
        V.DecodeValueBatch;
        Exit(0);
      end;
    WM_DRAWITEM:
      if Assigned(V) and (PCsvDrawItem(LParam)^.CtlType = ODT_BUTTON) then
      begin
        V.DrawTransformButton(PCsvDrawItem(LParam));
        Exit(1);
      end;
    WM_KEYDOWN:
      if Assigned(V) and (not V.FLoaded) then Exit(0)
      else if Assigned(V) and V.HandleEditKey(WParam) then Exit(0)
      else if ForwardViewerKey(V, WParam) then Exit(0);
    WM_SIZE:
      if Assigned(V) then begin V.Layout; Exit(0); end;
    WM_MOUSEWHEEL:
      if Assigned(V) and ((GetKeyState(VK_CONTROL) and $8000) <> 0) then
      begin
        if SmallInt(HiWord(WParam)) > 0 then V.SetFontSize(V.FFontSize + 1)
        else V.SetFontSize(V.FFontSize - 1);
        Exit(0);
      end;
    WM_CONTEXTMENU:
      if Assigned(V) then
      begin
        V.ShowGridMenu;
        Exit(0);
      end;
    WM_NOTIFY:
      if Assigned(V) then
      begin
        N := PNMHDR(LParam);
        if (not V.FLoaded) and (N^.hwndFrom = V.FGrid) then Exit(0);
        if (N^.hwndFrom = V.FGrid) and (Integer(N^.code) = LVN_GETDISPINFOW) then
        begin
          Item := PLVDispInfoW(LParam);
          Row := Item^.item.iItem;
          Column := Item^.item.iSubItem;
          if (Item^.item.mask and LVIF_TEXT) <> 0 then
          begin
            S := V.ActiveCellText(Row, Column);
            lstrcpynW(Item^.item.pszText, PWideChar(S), Item^.item.cchTextMax);
          end;
          Exit(0);
        end;
        if (N^.hwndFrom = V.FGrid) and (Integer(N^.code) = NM_CUSTOMDRAW) then
          Exit(V.CustomDraw(PNMLVCustomDraw(LParam)));
        if (N^.hwndFrom = V.FGrid) and (Integer(N^.code) = LVN_COLUMNCLICK) then
        begin
          if GetKeyState(VK_CONTROL) < 0 then
            V.HideColumn(PNMListView(LParam)^.iSubItem)
          else
            V.SortColumn(PNMListView(LParam)^.iSubItem);
          Exit(0);
        end;
        if (N^.hwndFrom = V.FHeader) and
          (Integer(N^.code) = NM_CUSTOMDRAW) then
          Exit(V.HeaderCustomDraw(PNMCustomDraw(LParam)));
        if (N^.hwndFrom = V.FHeader) and
          (Integer(N^.code) = NM_RCLICK) then
        begin
          FillChar(HeaderHit, SizeOf(HeaderHit), 0);
          GetCursorPos(P);
          HeaderHit.pt := P;
          ScreenToClient(V.FHeader, HeaderHit.pt);
          if SendMessageW(V.FHeader, HDM_HITTEST, 0,
            Windows.LPARAM(@HeaderHit)) >= 0 then
          begin
            V.CloseCellEdit(True);
            V.FCurrentRow := -1;
            V.FCurrentColumn := HeaderHit.iItem;
            V.ShowGridMenu;
          end;
          Exit(0);
        end;
        if (N^.hwndFrom = V.FGrid) and
          ((Integer(N^.code) = NM_CLICK) or (Integer(N^.code) = NM_DBLCLK) or
           (Integer(N^.code) = NM_RCLICK)) then
        begin
          V.CloseCellEdit(True);
          V.FCurrentRow := PNMItemActivate(LParam)^.iItem;
          V.FCurrentColumn := PNMItemActivate(LParam)^.iSubItem;
          InvalidateRect(V.FGrid, nil, False);
          V.UpdateStatus;
          if (Integer(N^.code) = NM_CLICK) and (GetKeyState(VK_MENU) < 0) then
            V.OpenCellUrl(V.FCurrentRow, V.FCurrentColumn);
          if Integer(N^.code) = NM_DBLCLK then
            V.BeginCellEdit(V.FCurrentRow, V.FCurrentColumn);
          Exit(0);
        end;
        if (N^.hwndFrom = V.FStatus) and
          ((Integer(N^.code) = NM_CLICK) or (Integer(N^.code) = NM_RCLICK)) then
        begin
          V.ShowStatusMenu(Integer(PNMMouse(LParam)^.dwItemSpec));
          Exit(0);
        end;
      end;
    WM_CLOSE:
      if Assigned(V) then
      begin
        if V.ConfirmChanges('closing') then DestroyWindow(Wnd);
        Exit(0);
      end;
    WM_NCDESTROY:
      begin
        SetWindowLongPtrW(Wnd, GWLP_USERDATA, 0);
        V.Free;
      end;
  end;
  Result := DefWindowProcW(Wnd, Msg, WParam, LParam);
end;

procedure EnsureViewerClass;
var
  WC: WNDCLASSEXW;
begin
  if GetClassInfoExW(HInstance, CSV_VIEWER_CLASS, @WC) then Exit;
  FillChar(WC, SizeOf(WC), 0);
  WC.cbSize := SizeOf(WC);
  WC.lpfnWndProc := @ViewerWndProc;
  WC.hInstance := HInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := HBRUSH(COLOR_WINDOW + 1);
  WC.lpszClassName := CSV_VIEWER_CLASS;
  RegisterClassExW(@WC);
end;

function CreateCsvViewer(ParentWin: HWND; const FileName: UnicodeString;
  ShowFlags: Integer): HWND;
var
  V: TCsvViewer;
  Init: TInitCommonControlsEx;
  GridStyles: DWORD;
  FontName: UnicodeString;
  FontSize, FontWeight, FontHeight: Integer;
  DC: HDC;
  ParentRect: TRect;
begin
  Result := 0;
  V := TCsvViewer.Create;
  V.FileName := FileName;
  V.FTakeInitialFocus := IsSeparateListerMode(ParentWin, ShowFlags);
  V.FCurrentRow := -1;
  V.FCurrentColumn := -1;
  case ReadStartMode of
    smEditor: V.FEditMode := True;
    smTransformer: V.FTransformMode := True;
  end;
  V.FFilterRow := ReadSettingInt('filter-row', 1) <> 0;
  V.FShowLineNumbers := ReadSettingInt('show-line-numbers', 0) <> 0;
  V.FDecimalAlign := ReadSettingInt('decimal-align', 1) <> 0;
  V.FSkipComments := ReadSettingInt('skip-comments', 0);
  V.FCommentsAuto := V.FSkipComments = 3;
  V.FTransform := TTransformConfig.Create;
  Init.dwSize := SizeOf(Init);
  Init.dwICC := ICC_LISTVIEW_CLASSES or ICC_BAR_CLASSES;
  InitCommonControlsEx(Init);
  EnsureViewerClass;
  FillChar(ParentRect, SizeOf(ParentRect), 0);
  GetClientRect(ParentWin, ParentRect);
  V.Wnd := CreateWindowExW(WS_EX_CONTROLPARENT or WS_EX_NOPARENTNOTIFY,
    CSV_VIEWER_CLASS, 'csvtab',
    WS_CHILD or WS_CLIPCHILDREN, 0, 0,
    ParentRect.Right - ParentRect.Left, ParentRect.Bottom - ParentRect.Top,
    ParentWin, 0, HInstance, nil);
  if V.Wnd = 0 then
  begin
    V.Free;
    Exit;
  end;
  SetWindowLongPtrW(V.Wnd, GWLP_USERDATA, PtrInt(V));
  V.FLoading := CreateWindowExW(0, 'STATIC', 'Loading...', WS_CHILD or
    WS_VISIBLE or SS_CENTER or SS_CENTERIMAGE, 0, 0, 100, 100, V.Wnd,
    IDC_LOADING, HInstance, nil);
  V.FGrid := CreateWindowExW(0, WC_LISTVIEWW, nil, WS_CHILD or
    WS_TABSTOP or LVS_REPORT or LVS_SHOWSELALWAYS or LVS_OWNERDATA, 0, 0,
    100, 100, V.Wnd, IDC_GRID, HInstance, nil);
  GridStyles := LVS_EX_FULLROWSELECT or LVS_EX_DOUBLEBUFFER;
  if ReadSettingInt('disable-grid-lines', 0) = 0 then
    GridStyles := GridStyles or LVS_EX_GRIDLINES;
  ListView_SetExtendedListViewStyle(V.FGrid, GridStyles);
  FontName := ReadSetting('font', 'Arial');
  FontSize := ReadSettingInt('font-size', 16);
  FontWeight := ReadSettingInt('font-weight', 0);
  if (FontWeight >= 1) and (FontWeight <= 9) then FontWeight := FontWeight * 100
  else FontWeight := FW_DONTCARE;
  V.FFontName := FontName;
  V.FFontSize := FontSize;
  V.FFontWeight := FontWeight;
  DC := GetDC(V.FGrid);
  if DC <> 0 then
  begin
    FontHeight := -MulDiv(FontSize, GetDeviceCaps(DC, LOGPIXELSY), 72);
    ReleaseDC(V.FGrid, DC);
  end
  else
    FontHeight := -FontSize;
  V.FGridFont := CreateFontW(FontHeight, 0, 0, 0, FontWeight, 0, 0, 0,
    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
    DEFAULT_PITCH or FF_DONTCARE, PWideChar(FontName));
  if V.FGridFont <> 0 then
  begin
    SendMessageW(V.FGrid, WM_SETFONT, WPARAM(V.FGridFont), 0);
    if IsWindow(V.FLoading) then
      SendMessageW(V.FLoading, WM_SETFONT, WPARAM(V.FGridFont), 0);
  end;
  V.SubclassChild(V.FGrid);
  V.FHeader := ListView_GetHeader(V.FGrid);
  V.FHeaderFont := CreateFontW(FontHeight, 0, 0, 0, FW_BOLD, 0, 0, 0,
    DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
    DEFAULT_PITCH or FF_DONTCARE, PWideChar(FontName));
  if V.FHeaderFont <> 0 then
    SendMessageW(V.FHeader, WM_SETFONT, WPARAM(V.FHeaderFont), 0);
  DisableWindowTheme(V.FHeader);
  V.ApplyTheme;
  V.FStatus := CreateStatusWindowW(WS_CHILD or WS_VISIBLE, nil, V.Wnd, IDC_STATUS);
  V.UpdateLoadingStatus;
  V.CreateTransformSidebar;
  V.CreateGridMenu;
  V.CreateStatusMenus;
  V.Layout;
  ShowWindow(V.Wnd, SW_SHOW);
  // Create the returned child at the current Lister client size so its first
  // visible layout is already correct. TC still owns subsequent resizing.
  V.FForwardKeysAfter := GetTickCount64 + 500;
  // Focus and document loading are deferred until after ListLoadW returns.
  // The short timer gives Total Commander a paint opportunity before large
  // CSV files are parsed and measured.
  SetTimer(V.Wnd, IDT_INITIAL_LOAD, 1, nil);
  Result := V.Wnd;
end;

procedure CloseCsvViewer(Wnd: HWND);
var
  V: TCsvViewer;
begin
  if not IsWindow(Wnd) then Exit;
  V := ViewerFromWnd(Wnd);
  if not Assigned(V) or V.ConfirmChanges('closing') then DestroyWindow(Wnd);
end;

function SearchCsvViewer(Wnd: HWND; const SearchText: UnicodeString;
  SearchFlags: Integer): Integer;
var
  V: TCsvViewer;
begin
  V := ViewerFromWnd(Wnd);
  if Assigned(V) then Result := V.Search(SearchText, SearchFlags)
  else Result := 0;
end;

end.
