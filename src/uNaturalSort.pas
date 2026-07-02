unit uNaturalSort;

{$mode delphi}{$H+}

interface

function NaturalCompare(const A, B: UnicodeString): Integer;

implementation

uses Windows, SysUtils;

const
  CSTR_EQUAL = 2;
  SORT_DIGITSASNUMBERS = $00000008;

function CompareStringEx(lpLocaleName: PWideChar; dwCmpFlags: DWORD;
  lpString1: PWideChar; cchCount1: Integer; lpString2: PWideChar;
  cchCount2: Integer; lpVersionInformation, lpReserved: Pointer;
  lParam: LPARAM): Integer; stdcall; external 'kernel32.dll' name 'CompareStringEx';

function NaturalCompare(const A, B: UnicodeString): Integer;
var
  R: Integer;
  DA, DB: Double;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if TryStrToFloat(UTF8Encode(A), DA, FS) and
    TryStrToFloat(UTF8Encode(B), DB, FS) then
  begin
    if DA < DB then Exit(-1);
    if DA > DB then Exit(1);
    Exit(0);
  end;
  R := CompareStringEx(nil, NORM_IGNORECASE or NORM_IGNOREWIDTH or
    SORT_DIGITSASNUMBERS, PWideChar(A), Length(A), PWideChar(B), Length(B),
    nil, nil, 0);
  if R = 0 then
  begin
    if A < B then Result := -1
    else if A > B then Result := 1
    else Result := 0;
  end
  else
    Result := R - CSTR_EQUAL;
end;

end.
