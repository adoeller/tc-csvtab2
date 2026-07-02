unit uSettings;

{$mode delphi}{$H+}

interface

uses Windows, SysUtils, Classes;

type
  TStartMode = (smDefault, smEditor, smTransformer);

procedure SetDefaultIniName(const AName: AnsiString);
function IniPath: UnicodeString;
function ReadSetting(const Name, Default: UnicodeString): UnicodeString;
function ReadSettingInt(const Name: UnicodeString; Default: Integer): Integer;
function ReadStartMode: TStartMode;
procedure WriteSettingInt(const Name: UnicodeString; Value: Integer);

implementation

var
  GDefaultIniPath: UnicodeString;

function IniPath: UnicodeString;
var
  Buf: array[0..MAX_PATH] of WideChar;
  LocalPath: UnicodeString;
begin
  GetModuleFileNameW(HInstance, Buf, MAX_PATH);
  LocalPath := ChangeFileExt(Buf, '.ini');
  if FileExists(LocalPath) or (GDefaultIniPath = '') then
    Result := LocalPath
  else
    Result := GDefaultIniPath;
end;

procedure SetDefaultIniName(const AName: AnsiString);
begin
  if GDefaultIniPath = '' then
    GDefaultIniPath := UnicodeString(AName);
end;

function IsValidUtf8(const B: TBytes): Boolean;
var
  I, N, J: Integer;
begin
  I := 0;
  while I < Length(B) do
  begin
    if B[I] < $80 then N := 0
    else if (B[I] and $E0) = $C0 then N := 1
    else if (B[I] and $F0) = $E0 then N := 2
    else if (B[I] and $F8) = $F0 then N := 3
    else Exit(False);
    if I + N >= Length(B) then Exit(False);
    for J := 1 to N do
      if (B[I + J] and $C0) <> $80 then Exit(False);
    Inc(I, N + 1);
  end;
  Result := True;
end;

function LoadIniText(const Path: UnicodeString): UnicodeString;
var
  F: TFileStream;
  B: TBytes;
  A: AnsiString;
  Start, Count: Integer;
begin
  Result := '';
  if not FileExists(Path) then Exit;
  F := TFileStream.Create(UTF8Encode(Path), fmOpenRead or fmShareDenyNone);
  try
    SetLength(B, F.Size);
    if F.Size > 0 then F.ReadBuffer(B[0], F.Size);
  finally
    F.Free;
  end;
  Start := 0;
  if (Length(B) >= 3) and (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF) then
    Start := 3;
  if IsValidUtf8(B) then
  begin
    if Length(B) > Start then
      SetString(A, PAnsiChar(@B[Start]), Length(B) - Start)
    else
      A := '';
    Exit(UTF8Decode(A));
  end;
  if Length(B) = 0 then Exit;
  SetString(A, PAnsiChar(@B[0]), Length(B));
  Count := MultiByteToWideChar(CP_ACP, 0, PAnsiChar(A), Length(A), nil, 0);
  SetLength(Result, Count);
  if Count > 0 then
    MultiByteToWideChar(CP_ACP, 0, PAnsiChar(A), Length(A),
      PWideChar(Result), Count);
end;

function StripInlineComment(const Value: UnicodeString): UnicodeString;
var
  I: Integer;
  Quote: WideChar;
begin
  Quote := #0;
  I := 1;
  while I <= Length(Value) do
  begin
    if (Value[I] = '"') or (Value[I] = '''') then
    begin
      if Quote = #0 then Quote := Value[I]
      else if Quote = Value[I] then Quote := #0;
    end
    else if (Quote = #0) and (Value[I] in [';', '#']) and (I > 1) and
      (Value[I - 1] <= ' ') then
      Exit(TrimRight(Copy(Value, 1, I - 1)));
    Inc(I);
  end;
  Result := TrimRight(Value);
end;

function Unquote(const Value: UnicodeString): UnicodeString;
begin
  Result := Trim(Value);
  if (Length(Result) >= 2) and
    (((Result[1] = '"') and (Result[Length(Result)] = '"')) or
    ((Result[1] = '''') and (Result[Length(Result)] = ''''))) then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

function ReadSetting(const Name, Default: UnicodeString): UnicodeString;
var
  Lines: TStringList;
  I, P: Integer;
  Line, Section, Key, Value: UnicodeString;
begin
  Result := Default;
  Lines := TStringList.Create;
  try
    Lines.Text := UTF8Encode(LoadIniText(IniPath));
    Section := '';
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(UTF8Decode(Lines[I]));
      if (Line = '') or (Line[1] in [';', '#']) then Continue;
      if (Line[1] = '[') and (Line[Length(Line)] = ']') then
      begin
        Section := Trim(Copy(Line, 2, Length(Line) - 2));
        Continue;
      end;
      if not SameText(Section, 'csvtab') then Continue;
      P := Pos('=', Line);
      if P = 0 then Continue;
      Key := Trim(Copy(Line, 1, P - 1));
      if not SameText(Key, Name) then Continue;
      Value := StripInlineComment(Copy(Line, P + 1, MaxInt));
      Exit(Unquote(Value));
    end;
  finally
    Lines.Free;
  end;
end;

function ReadSettingInt(const Name: UnicodeString; Default: Integer): Integer;
begin
  Result := StrToIntDef(Trim(ReadSetting(Name, IntToStr(Default))), Default);
end;

function ReadStartMode: TStartMode;
var
  Value: UnicodeString;
begin
  Value := UnicodeLowerCase(Trim(ReadSetting('start-mode', 'default')));
  if (Value = 'editor') or (Value = 'editor mode') or
    (Value = 'edit') or (Value = 'edit mode') or (Value = '1') then
    Result := smEditor
  else if (Value = 'transformer') or (Value = 'transformer mode') or
    (Value = 'transform') or (Value = 'transform mode') or (Value = '2') then
    Result := smTransformer
  else
    Result := smDefault;
end;

procedure WriteSettingInt(const Name: UnicodeString; Value: Integer);
begin
  WritePrivateProfileStringW('csvtab', PWideChar(Name),
    PWideChar(UnicodeString(IntToStr(Value))), PWideChar(IniPath));
end;

end.
