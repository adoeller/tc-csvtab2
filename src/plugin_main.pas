unit plugin_main;

{$mode delphi}{$H+}

interface

uses Windows, SysUtils, listplug;

function ListLoad(ParentWin: HWND; FileToLoad: PAnsiChar; ShowFlags: Integer): HWND; stdcall;
function ListLoadW(ParentWin: HWND; FileToLoad: PWideChar; ShowFlags: Integer): HWND; stdcall;
procedure ListCloseWindow(ListWin: HWND); stdcall;
procedure ListGetDetectString(DetectString: PAnsiChar; MaxLen: Integer); stdcall;
procedure ListSetDefaultParams(Dps: PListDefaultParamStruct); stdcall;
function ListSearchText(ListWin: HWND; SearchString: PAnsiChar; SearchParameter: Integer): Integer; stdcall;
function ListSearchTextW(ListWin: HWND; SearchString: PWideChar; SearchParameter: Integer): Integer; stdcall;

implementation

uses uSettings, uViewer;

function ListLoadW(ParentWin: HWND; FileToLoad: PWideChar;
  ShowFlags: Integer): HWND; stdcall;
begin
  Result := CreateCsvViewer(ParentWin, FileToLoad, ShowFlags);
end;

function ListLoad(ParentWin: HWND; FileToLoad: PAnsiChar;
  ShowFlags: Integer): HWND; stdcall;
begin
  Result := ListLoadW(ParentWin,
    PWideChar(UnicodeString(AnsiString(FileToLoad))), ShowFlags);
end;

procedure ListCloseWindow(ListWin: HWND); stdcall;
begin
  CloseCsvViewer(ListWin);
end;

procedure ListGetDetectString(DetectString: PAnsiChar; MaxLen: Integer); stdcall;
var
  S: AnsiString;
begin
  S := UTF8Encode(ReadSetting('detect-string',
    'MULTIMEDIA & (ext="CSV" | ext="TAB" | ext="TSV")'));
  StrLCopy(DetectString, PAnsiChar(S), MaxLen - 1);
end;

procedure ListSetDefaultParams(Dps: PListDefaultParamStruct); stdcall;
begin
  if Assigned(Dps) then
    SetDefaultIniName(AnsiString(PAnsiChar(@Dps^.DefaultIniName[0])));
end;

function ListSearchTextW(ListWin: HWND; SearchString: PWideChar;
  SearchParameter: Integer): Integer; stdcall;
begin
  Result := SearchCsvViewer(ListWin, SearchString, SearchParameter);
end;

function ListSearchText(ListWin: HWND; SearchString: PAnsiChar;
  SearchParameter: Integer): Integer; stdcall;
begin
  Result := ListSearchTextW(ListWin,
    PWideChar(UnicodeString(AnsiString(SearchString))), SearchParameter);
end;

end.
