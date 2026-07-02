unit uDecimalAlign;

{$mode delphi}{$H+}

interface

uses SysUtils;

function SplitDecimalText(const Value: UnicodeString; out IntegerPart,
  FractionPart: UnicodeString; out Separator: WideChar): Boolean;
function IsIntegerText(const Value: UnicodeString): Boolean;

implementation

function IsIntegerText(const Value: UnicodeString): Boolean;
var
  S: UnicodeString;
  I, FirstDigit: Integer;
begin
  Result := False;
  S := Trim(Value);
  if S = '' then Exit;
  FirstDigit := 1;
  if S[1] in ['+', '-'] then FirstDigit := 2;
  if FirstDigit > Length(S) then Exit;
  for I := FirstDigit to Length(S) do
    if not (S[I] in ['0'..'9']) then Exit;
  Result := True;
end;

function SplitDecimalText(const Value: UnicodeString; out IntegerPart,
  FractionPart: UnicodeString; out Separator: WideChar): Boolean;
var
  S: UnicodeString;
  I, SeparatorPos: Integer;
begin
  Result := False;
  IntegerPart := '';
  FractionPart := '';
  Separator := #0;
  S := Trim(Value);
  if S = '' then Exit;
  SeparatorPos := 0;
  for I := 1 to Length(S) do
    if S[I] in [',', '.'] then
    begin
      if SeparatorPos <> 0 then Exit;
      SeparatorPos := I;
      Separator := S[I];
    end
    else if not ((S[I] >= '0') and (S[I] <= '9')) and
      not ((I = 1) and (S[I] in ['+', '-'])) then Exit;
  if (SeparatorPos <= 1) or (SeparatorPos >= Length(S)) then Exit;
  if (SeparatorPos = 2) and (S[1] in ['+', '-']) then Exit;
  IntegerPart := Copy(S, 1, SeparatorPos - 1);
  FractionPart := Copy(S, SeparatorPos + 1, MaxInt);
  Result := True;
end;

end.
