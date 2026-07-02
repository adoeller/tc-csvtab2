unit uCsvSave;

{$mode delphi}{$H+}

interface

uses Windows, SysUtils, Classes, uCsvModel;

function SaveCsvSourceAtomic(const FileName, SourceText: UnicodeString;
  const Encoding: TCsvEncodingInfo; Delimiter: WideChar; SkipComments: Integer;
  TrimValues: Boolean): Boolean;

implementation

const
  CSV_REPLACEFILE_WRITE_THROUGH = $00000001;
  CSV_MOVEFILE_REPLACE_EXISTING = $00000001;
  CSV_MOVEFILE_WRITE_THROUGH = $00000008;

function ReplaceFileW(lpReplacedFileName, lpReplacementFileName,
  lpBackupFileName: PWideChar; dwReplaceFlags: DWORD;
  lpExclude, lpReserved: Pointer): BOOL; stdcall; external 'kernel32.dll';

function SourceToBytes(const SourceText: UnicodeString;
  const Encoding: TCsvEncodingInfo; out B: TBytes): Boolean;
var
  U: UTF8String;
  Count, I, Start: Integer;
  UsedDefault: BOOL;
begin
  Result := False;
  SetLength(B, 0);
  if SameText(Encoding.Name, 'UTF-8') then
  begin
    U := UTF8Encode(SourceText);
    Start := Ord(Encoding.HasBom) * 3;
    SetLength(B, Start + Length(U));
    if Encoding.HasBom then
    begin
      B[0] := $EF;
      B[1] := $BB;
      B[2] := $BF;
    end;
    if Length(U) > 0 then Move(PAnsiChar(U)^, B[Start], Length(U));
    Exit(True);
  end;
  if SameText(Encoding.Name, 'UTF-16LE') or
    SameText(Encoding.Name, 'UTF-16BE') then
  begin
    Start := Ord(Encoding.HasBom) * 2;
    SetLength(B, Start + Length(SourceText) * 2);
    if Encoding.HasBom then
      if SameText(Encoding.Name, 'UTF-16LE') then
      begin
        B[0] := $FF;
        B[1] := $FE;
      end
      else
      begin
        B[0] := $FE;
        B[1] := $FF;
      end;
    for I := 1 to Length(SourceText) do
      if SameText(Encoding.Name, 'UTF-16LE') then
      begin
        B[Start + (I - 1) * 2] := Ord(SourceText[I]) and $FF;
        B[Start + (I - 1) * 2 + 1] := Ord(SourceText[I]) shr 8;
      end
      else
      begin
        B[Start + (I - 1) * 2] := Ord(SourceText[I]) shr 8;
        B[Start + (I - 1) * 2 + 1] := Ord(SourceText[I]) and $FF;
      end;
    Exit(True);
  end;
  if not SameText(Encoding.Name, 'ANSI') then Exit;

  UsedDefault := False;
  Count := WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS,
    PWideChar(SourceText), Length(SourceText), nil, 0, nil, @UsedDefault);
  if (Count < 0) or UsedDefault then Exit;
  SetLength(B, Count);
  UsedDefault := False;
  if Count > 0 then
    WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS, PWideChar(SourceText),
      Length(SourceText), PAnsiChar(@B[0]), Count, nil, @UsedDefault);
  Result := not UsedDefault;
end;

function SaveCsvSourceAtomic(const FileName, SourceText: UnicodeString;
  const Encoding: TCsvEncodingInfo; Delimiter: WideChar; SkipComments: Integer;
  TrimValues: Boolean): Boolean;
var
  B: TBytes;
  Dir, TempName: UnicodeString;
  TempBuf: array[0..MAX_PATH] of WideChar;
  H: THandle;
  Written: DWORD;
  CheckDoc: TCsvDocument;
begin
  Result := False;
  CheckDoc := nil;
  if not SourceToBytes(SourceText, Encoding, B) then Exit;
  Dir := ExtractFilePath(FileName);
  if Dir = '' then Dir := GetCurrentDir;
  if GetTempFileNameW(PWideChar(Dir), 'cst', 0, @TempBuf[0]) = 0 then Exit;
  TempName := TempBuf;
  try
    H := CreateFileW(PWideChar(TempName), GENERIC_WRITE, 0, nil, CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL, 0);
    if H = INVALID_HANDLE_VALUE then Exit;
    try
      if Length(B) > 0 then
      begin
        Written := 0;
        if not WriteFile(H, B[0], Length(B), Written, nil) or
          (Written <> DWORD(Length(B))) then Exit;
      end;
      if not FlushFileBuffers(H) then Exit;
    finally
      CloseHandle(H);
    end;
    if not LoadCsvFileAs(TempName, 0, Delimiter, SkipComments, Encoding.Name,
      CheckDoc, TrimValues) then Exit;
    if (CheckDoc.SourceText <> SourceText) or
      not SameText(CheckDoc.Encoding.Name, Encoding.Name) or
      (CheckDoc.Encoding.HasBom <> Encoding.HasBom) then Exit;
    FreeAndNil(CheckDoc);
    if not ReplaceFileW(PWideChar(FileName), PWideChar(TempName), nil,
      CSV_REPLACEFILE_WRITE_THROUGH, nil, nil) then
      if not MoveFileExW(PWideChar(TempName), PWideChar(FileName),
        CSV_MOVEFILE_REPLACE_EXISTING or CSV_MOVEFILE_WRITE_THROUGH) then Exit;
    TempName := '';
    Result := True;
  finally
    CheckDoc.Free;
    if TempName <> '' then DeleteFileW(PWideChar(TempName));
  end;
end;

end.
