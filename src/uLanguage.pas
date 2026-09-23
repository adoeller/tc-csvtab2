unit uLanguage;

{$mode delphi}{$H+}
// The alias tables below contain non-ASCII language names, so the source file
// has to be read as UTF-8 for them to survive the conversion to UnicodeString.
{$codepage utf8}

// GUI catalogs for csvtab.
//
// Every catalog is a small UTF-8 INI file in a `language` directory next to the
// plugin DLL ("language\zh-CN.lng", ...). A complete English catalog is also
// compiled into the plugin, so a missing or unreadable catalog can never expose
// internal translation keys in the GUI.
//
// The `language` setting in csvtab.ini selects the catalog:
//
//   language = Auto               follow Total Commander (default)
//   language = German             ... or Deutsch, de, deu, wcmd_deu.lng
//   language = English            ... or english, en, eng
//   language = Ukrainian          ... or ukrainisch, uk, ukr
//   language = Russian            ... or russisch, ru, rus
//   language = SimplifiedChinese  ... or zh-CN, chn, 简体中文
//   language = TraditionalChinese ... or zh-TW, cht, tw, 繁體中文
//
// `Auto` reads `LanguageIni` from the `[Configuration]` section of Total
// Commander's wincmd.ini, so the plugin starts in the same language as Total
// Commander (`wcmd_chn.lng` -> Simplified Chinese, `wcmd_tw.lng` or
// `wcmd_cht.lng` -> Traditional Chinese, `wcmd_deu.lng` -> German, ...).

interface

uses Windows, SysUtils;

type
  TLanguageId = (liEnglish, liGerman, liUkrainian, liRussian,
    liChineseSimplified, liChineseTraditional,
    // A catalog that was loaded by file name because the `language` value is
    // not one of the known aliases.
    liCustom);

// Resolves a `language=` value, a Total Commander `LanguageIni` file name, a
// language code or a native language name to a catalog id. Unknown values
// resolve to liEnglish.
function LangNameToId(const Value: UnicodeString): TLanguageId;
// The catalog base name without extension, e.g. 'zh-CN'.
function LangIdToCode(Id: TLanguageId): UnicodeString;
// The catalog the GUI currently uses.
function CurrentLanguage: TLanguageId;
// Evaluates the `language` setting, including `Auto` detection.
function DetectLanguage: TLanguageId;
// Reads a value from Total Commander's own wincmd.ini. Used by the `Auto`
// language detection for `[Configuration] LanguageIni`.
function ReadTcIniSetting(const Section, Key: UnicodeString): UnicodeString;
// Loads a catalog; entries missing from the file keep their English text.
procedure LangLoad(Id: TLanguageId);
// DetectLanguage + LangLoad; called once while the viewer is created.
procedure LangLoadDefault;
// Translation lookup. Unknown keys return the key itself.
function Lang(const Key: UnicodeString): UnicodeString;
// Translation lookup for catalogs with %d placeholders.
function LangInt(const Key: UnicodeString; const Values: array of Integer): UnicodeString;
// Translation lookup for catalogs with %s placeholders. Values are real
// UnicodeStrings, so file names and column headers keep their characters.
function LangStr(const Key: UnicodeString; const Values: array of UnicodeString): UnicodeString;

implementation

uses uSettings;

const
  // Complete built-in fallback catalog; keep in sync with language\en.lng.
  EnglishCatalog: array[0..64] of UnicodeString = (
    'Loading=Loading...',
    'Delimiter=Delimiter',
    'Auto=Auto',
    'CommentsAuto=Comments: auto (%d)',
    'CommentsNoParse=Comments: unparsed (0)',
    'CommentsHidden=Comments: hidden (%d)',
    'CommentsParse=Comments: parsed normally (0)',
    'Rows=Rows: %d/%d',
    'Edit=EDIT',
    'Modified=MODIFIED',
    'Transform=TRANSFORM',
    'Selected=Selected: %d rows, %d columns',
    'FileSaveFailed=The file could not be saved.',
    'SaveBefore=Save changes to "%s" before %s?',
    'Reloading=reloading',
    'Closing=closing',
    'DeleteColumnQuestion=Delete column "%s"?',
    'AllFiles=All files',
    'Up=Up',
    'Down=Down',
    'AddColumn=+ Add column',
    'RemoveColumn=- Remove column',
    'RenameColumn=~ Rename column',
    'SetAllCells=Set all cells',
    'FillEmptyCells=Fill empty cells',
    'EnumerateCells=Fill cells with sequence',
    'LoadTransformation=Load transformation (JSON)',
    'SaveTransformation=Save transformation (JSON)',
    'NumberFormat=Number format',
    'ExportCsv=Export CSV',
    'ApplyToGrid=Apply to grid',
    'ResetGridView=Reset grid view',
    'TransformInputHint=Value / name / sequence start:end',
    'LoadTransformationFailed=Could not load transformation JSON.',
    'SaveTransformationFailed=Could not save transformation JSON.',
    'ExportTransformationFailed=Could not export transformed CSV.',
    'CopyCell=Copy cell',
    'CopyRows=Copy row(s) (Shift+C)',
    'CopyColumn=Copy column (Ctrl+C)',
    'InsertRowBelow=Insert row below',
    'DeleteRows=Delete row(s) (Ctrl+X)',
    'DeleteColumn=Delete column',
    'HideColumn=Hide column (Ctrl+Click)',
    'AdjustAllColumnsWidth=Auto-size all columns (Ctrl+H)',
    'ShowAllColumns=Show all columns (Ctrl+Space)',
    'Filters=Filters',
    'HeaderRow=Header row',
    'EditMode=Edit mode (Ctrl+E)',
    'TransformMode=Transform mode (Ctrl+T)',
    'Save=Save (Ctrl+S)',
    'ShowLineNumbers=Show line numbers',
    'Theme=Theme',
    'ThemeTc=Total Commander',
    'ThemeLight=Light',
    'ThemeDark=Dark',
    'ParseNormally=Parse normally',
    'DoNotParse=Do not parse',
    'Hide=Hide',
    'FileReloadFailed=The file could not be reloaded.',
    'FileLoadFailed=The file could not be loaded.',
    'FileTooLarge=The file could not be loaded because it exceeds the configured size limit.',
    'FileSize=File size',
    'Limit=Limit',
    'Column=Column %d',
    'Original=original'
  );

var
  // Parallel arrays instead of a TStringList: FPC's TStringList stores
  // AnsiString, which would mangle the non-ASCII catalog values.
  CatalogKeys: array of UnicodeString;
  CatalogValues: array of UnicodeString;
  Current: TLanguageId = liEnglish;

// Case-insensitive comparison for catalog keys, INI keys and sections. All of
// them are ASCII, but SysUtils.SameText takes AnsiString, which would convert
// and silently mangle the values passing through here.
function SameKey(const A, B: UnicodeString): Boolean;
begin
  if Length(A) <> Length(B) then Exit(False);
  Result := UnicodeLowerCase(A) = UnicodeLowerCase(B);
end;

function MatchesAny(const Value: UnicodeString;
  const Aliases: array of UnicodeString): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Aliases) do
    if Value = Aliases[I] then Exit(True);
  Result := False;
end;

procedure SetEntry(const Name, Value: UnicodeString);
var
  I: Integer;
begin
  for I := 0 to High(CatalogKeys) do
    if SameKey(CatalogKeys[I], Name) then
    begin
      CatalogValues[I] := Value;
      Exit;
    end;
  SetLength(CatalogKeys, Length(CatalogKeys) + 1);
  SetLength(CatalogValues, Length(CatalogValues) + 1);
  CatalogKeys[High(CatalogKeys)] := Name;
  CatalogValues[High(CatalogValues)] := Value;
end;

function GetEntry(const Name: UnicodeString): UnicodeString;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(CatalogKeys) do
    if SameKey(CatalogKeys[I], Name) then Exit(CatalogValues[I]);
end;

function PluginDirectory: UnicodeString;
var
  Buf: array[0..MAX_PATH - 1] of WideChar;
begin
  Result := '';
  if GetModuleFileNameW(HInstance, Buf, Length(Buf)) > 0 then
    Result := ExtractFileDir(Buf);
end;

// Lower-cases, trims, drops any directory, extension and the `wcmd_` prefix of
// a Total Commander language file, so 'WCMD_CHN.LNG', 'wcmd_chn' and 'chn' all
// become 'chn'.
function NormalizeLanguageToken(const Value: UnicodeString): UnicodeString;
var
  S: UnicodeString;
  P, I: Integer;
begin
  S := UnicodeLowerCase(Trim(Value));
  if (Length(S) >= 2) and (S[1] = '"') and (S[Length(S)] = '"') then
    S := Trim(Copy(S, 2, Length(S) - 2));
  // Scan for the last path delimiter by character, not with LastDelimiter():
  // that one takes an AnsiString and would convert (and mangle) S.
  P := 0;
  for I := Length(S) downto 1 do
    if (S[I] = '\') or (S[I] = '/') or (S[I] = ':') then
    begin
      P := I;
      Break;
    end;
  if P > 0 then S := Copy(S, P + 1, MaxInt);
  P := Length(S);
  if (P > 4) and (S[P - 3] = '.') then
  begin
    if (Copy(S, P - 2, 3) = 'lng') or (Copy(S, P - 2, 3) = 'inc') or
      (Copy(S, P - 2, 3) = 'mnu') then
      SetLength(S, P - 4);
  end;
  if (Length(S) > 5) and (Copy(S, 1, 5) = 'wcmd_') then S := Copy(S, 6, MaxInt);
  Result := Trim(S);
end;

function IsAutoValue(const Value: UnicodeString): Boolean;
var
  S: UnicodeString;
begin
  S := NormalizeLanguageToken(Value);
  Result := (S = '') or (S = 'auto') or (S = 'system') or (S = 'default');
end;

function LangNameToId(const Value: UnicodeString): TLanguageId;
var
  S: UnicodeString;
begin
  Result := liEnglish;
  S := NormalizeLanguageToken(Value);
  if S = '' then Exit;
  if MatchesAny(S, ['de', 'deu', 'ger', 'german', 'deutsch']) then
    Exit(liGerman);
  if MatchesAny(S, ['uk', 'ukr', 'ua', 'ukrainian', 'ukrainisch',
    'українська']) then
    Exit(liUkrainian);
  if MatchesAny(S, ['ru', 'rus', 'russian', 'russisch', 'русский']) then
    Exit(liRussian);
  if MatchesAny(S, ['en', 'eng', 'english', 'englisch']) then
    Exit(liEnglish);
  // Simplified Chinese. 'chn' is the code used by Total Commander
  // (wcmd_chn.lng); 'chs' and 'zh-cn' are the common alternatives.
  if MatchesAny(S, ['chn', 'chs', 'cn', 'zh', 'zhcn', 'zh-cn', 'zh_cn',
    'zh-hans', 'chinese', 'chinesesimplified', 'simplified',
    'simplifiedchinese', 'chinese (simplified)', 'chinese simplified',
    'simplified chinese', '简体中文', '简体', '中文']) then
    Exit(liChineseSimplified);
  // Traditional Chinese. 'cht' is the code used by Total Commander
  // (wcmd_cht.lng); the older Traditional pack uses wcmd_tw.lng.
  if MatchesAny(S, ['cht', 'tw', 'zhtw', 'zh-tw', 'zh_tw', 'zh-hant', 'zh-hk',
    'hk', 'chinesetraditional', 'traditional', 'traditionalchinese',
    'chinese (traditional)', 'chinese traditional', 'traditional chinese',
    '繁體中文', '繁体中文', '繁體', '繁体']) then
    Exit(liChineseTraditional);
end;

function LangIdToCode(Id: TLanguageId): UnicodeString;
begin
  case Id of
    liGerman: Result := 'de';
    liUkrainian: Result := 'uk';
    liRussian: Result := 'ru';
    liChineseSimplified: Result := 'zh-CN';
    liChineseTraditional: Result := 'zh-TW';
  else
    Result := 'en';
  end;
end;

function CurrentLanguage: TLanguageId;
begin
  Result := Current;
end;

// Extracts the line starting at Start (1-based) and moves Start behind the line
// break. Text is scanned as UnicodeString, so no code page conversion is
// involved anywhere.
function NextIniLine(const Text: UnicodeString; var Start: Integer;
  out Line: UnicodeString): Boolean;
var
  E: Integer;
begin
  Result := False;
  if Start > Length(Text) then Exit;
  E := Start;
  while (E <= Length(Text)) and (Text[E] <> #13) and (Text[E] <> #10) do Inc(E);
  Line := Copy(Text, Start, E - Start);
  while (E <= Length(Text)) and ((Text[E] = #13) or (Text[E] = #10)) do Inc(E);
  Start := E;
  Result := True;
end;

// Reads `Key` from `Section` of an already decoded INI/.lng text. An empty
// Section matches keys outside any section.
function ReadIniValue(const Text, Section, Key: UnicodeString): UnicodeString;
var
  Scan, P: Integer;
  Line, CurrentSection, Name, Value: UnicodeString;
begin
  Result := '';
  Scan := 1;
  CurrentSection := '';
  while NextIniLine(Text, Scan, Line) do
  begin
    Line := Trim(Line);
    if (Line = '') or (Line[1] = ';') or (Line[1] = '#') then Continue;
    if (Line[1] = '[') and (Line[Length(Line)] = ']') then
    begin
      CurrentSection := Trim(Copy(Line, 2, Length(Line) - 2));
      Continue;
    end;
    if (Section <> '') and not SameKey(CurrentSection, Section) then Continue;
    P := System.Pos('=', Line);
    if P = 0 then Continue;
    Name := Trim(Copy(Line, 1, P - 1));
    if not SameKey(Name, Key) then Continue;
    Value := Trim(Copy(Line, P + 1, MaxInt));
    if (Length(Value) >= 2) and (Value[1] = '"') and
      (Value[Length(Value)] = '"') then
      Value := Copy(Value, 2, Length(Value) - 2);
    Exit(Value);
  end;
end;

// Total Commander's wincmd.ini. `COMMANDER_INI` is set by Total Commander
// itself; walking up from the plugin directory is the fallback, because
// wincmd.ini usually sits next to TotalCMD.exe a few levels above
// Plugins\Wlx\csvtab.
function TcIniPath: UnicodeString;
var
  Dir, Candidate: UnicodeString;
  I: Integer;
begin
  Result := '';
  Candidate := Trim(UnicodeString(GetEnvironmentVariable('COMMANDER_INI')));
  if (Candidate <> '') and FileExists(Candidate) then Exit(Candidate);
  Dir := PluginDirectory;
  for I := 0 to 3 do
  begin
    if Dir = '' then Break;
    Candidate := IncludeTrailingPathDelimiter(Dir) + 'wincmd.ini';
    if FileExists(Candidate) then Exit(Candidate);
    Dir := ExtractFileDir(Dir);
  end;
end;

function TcLanguageIni: UnicodeString;
begin
  Result := ReadTcIniSetting('Configuration', 'LanguageIni');
end;

function ReadTcIniSetting(const Section, Key: UnicodeString): UnicodeString;
var
  Path: UnicodeString;
begin
  Result := '';
  Path := TcIniPath;
  if Path = '' then Exit;
  Result := ReadIniValue(LoadTextFile(Path), Section, Key);
end;

function DetectLanguage: TLanguageId;
var
  Value: UnicodeString;
begin
  Value := ReadSetting('language', 'Auto');
  if not IsAutoValue(Value) then Exit(LangNameToId(Value));
  Result := LangNameToId(TcLanguageIni);
end;

// 'language\xx.lng' next to the DLL, then in up to three parent directories so
// that the layout <plugin>\csvtab.wlx + <plugin>\language also works.
function FindCatalogFile(const Code: UnicodeString): UnicodeString;
var
  Dir: UnicodeString;
  I: Integer;
begin
  Result := '';
  if Code = '' then Exit;
  Dir := PluginDirectory;
  for I := 0 to 3 do
  begin
    if Dir = '' then Break;
    Result := IncludeTrailingPathDelimiter(Dir) + 'language' +
      PathDelim + Code + '.lng';
    if FileExists(Result) then Exit;
    // Be forgiving about the exact spelling of the file name; the Windows file
    // system is case-insensitive, a checkout on another system may not be.
    Result := IncludeTrailingPathDelimiter(Dir) + 'language' +
      PathDelim + UnicodeLowerCase(Code) + '.lng';
    if FileExists(Result) then Exit;
    Dir := ExtractFileDir(Dir);
  end;
  Result := '';
end;

function CatalogPath(Id: TLanguageId): UnicodeString;
begin
  Result := FindCatalogFile(LangIdToCode(Id));
end;

// Overlays every `key=value` line of a catalog text onto the current catalog.
procedure ApplyCatalog(const Text: UnicodeString);
var
  Scan, P: Integer;
  Line, Name, Value: UnicodeString;
begin
  Scan := 1;
  while NextIniLine(Text, Scan, Line) do
  begin
    Line := Trim(Line);
    if (Line = '') or (Line[1] = ';') or (Line[1] = '#') or (Line[1] = '[') then
      Continue;
    P := System.Pos('=', Line);
    if P = 0 then Continue;
    Name := Trim(Copy(Line, 1, P - 1));
    Value := Trim(Copy(Line, P + 1, MaxInt));
    if (Name = '') or (Value = '') then Continue;
    SetEntry(Name, Value);
  end;
end;

procedure ApplyEnglishCatalog;
var
  I, P: Integer;
  Line: UnicodeString;
begin
  for I := 0 to High(EnglishCatalog) do
  begin
    Line := EnglishCatalog[I];
    P := System.Pos('=', Line);
    if P = 0 then Continue;
    SetEntry(Copy(Line, 1, P - 1), Copy(Line, P + 1, MaxInt));
  end;
end;

procedure LangLoad(Id: TLanguageId);
var
  Path: UnicodeString;
begin
  SetLength(CatalogKeys, 0);
  SetLength(CatalogValues, 0);
  ApplyEnglishCatalog;
  Path := CatalogPath(Id);
  if Path <> '' then ApplyCatalog(LoadTextFile(Path));
  Current := Id;
end;

// Loads an arbitrary catalog on top of the built-in English one.
procedure LangLoadFromFile(const Path: UnicodeString);
begin
  SetLength(CatalogKeys, 0);
  SetLength(CatalogValues, 0);
  ApplyEnglishCatalog;
  ApplyCatalog(LoadTextFile(Path));
  Current := liCustom;
end;

procedure LangLoadDefault;
var
  Value, Name, Path: UnicodeString;
  Id: TLanguageId;
begin
  Value := ReadSetting('language', 'Auto');
  if IsAutoValue(Value) then
  begin
    LangLoad(DetectLanguage);
    Exit;
  end;
  Id := LangNameToId(Value);
  // A value that is not a known alias is used directly as a catalog file name,
  // so a new language can be shipped as a single .lng file.
  if Id = liEnglish then
  begin
    Name := NormalizeLanguageToken(Value);
    if (Name <> 'en') and (Name <> 'eng') and (Name <> 'english') and
      (Name <> 'englisch') then
    begin
      Path := FindCatalogFile(Name);
      if Path <> '' then
      begin
        LangLoadFromFile(Path);
        Exit;
      end;
    end;
  end;
  LangLoad(Id);
end;

function Lang(const Key: UnicodeString): UnicodeString;
begin
  Result := GetEntry(Key);
  if Result = '' then Result := Key;
end;

// Replaces the %d / %s placeholders of a catalog value. SysUtils.Format() is
// deliberately not used: it takes an AnsiString and therefore converts the
// format text to the system code page, which destroys every character that is
// not part of it (Chinese on a Russian Windows, umlauts on a Chinese one, ...).
// Only %d, %s and %% occur in the catalogs.
function FormatCatalog(const Fmt: UnicodeString;
  const Values: array of UnicodeString): UnicodeString;
var
  I, ArgIndex: Integer;
begin
  Result := '';
  ArgIndex := 0;
  I := 1;
  while I <= Length(Fmt) do
  begin
    if Fmt[I] <> '%' then
    begin
      Result := Result + Fmt[I];
      Inc(I);
      Continue;
    end;
    if I = Length(Fmt) then
    begin
      Result := Result + '%';
      Break;
    end;
    case Fmt[I + 1] of
      '%':
        begin
          Result := Result + '%';
          Inc(I, 2);
        end;
      's', 'd':
        begin
          if ArgIndex <= High(Values) then Result := Result + Values[ArgIndex];
          Inc(ArgIndex);
          Inc(I, 2);
        end;
    else
      begin
        // Unknown specifier: keep it verbatim.
        Result := Result + Fmt[I];
        Inc(I);
      end;
    end;
  end;
end;

function LangInt(const Key: UnicodeString;
  const Values: array of Integer): UnicodeString;
var
  S: array of UnicodeString;
  I: Integer;
begin
  SetLength(S, Length(Values));
  for I := 0 to High(Values) do S[I] := IntToStr(Values[I]);
  Result := FormatCatalog(Lang(Key), S);
end;

function LangStr(const Key: UnicodeString;
  const Values: array of UnicodeString): UnicodeString;
begin
  Result := FormatCatalog(Lang(Key), Values);
end;

initialization
  ApplyEnglishCatalog;
  Current := liEnglish;

end.
