unit uUrlTools;

{$mode delphi}{$H+}

interface

uses SysUtils;

function ExtractCellUrl(const Value: UnicodeString): UnicodeString;

implementation

function ExtractCellUrl(const Value: UnicodeString): UnicodeString;
var
  SchemePos, StartPos, EndPos: Integer;
begin
  Result := '';
  SchemePos := Pos('://', Value);
  if SchemePos > 0 then
  begin
    StartPos := SchemePos - 1;
    while (StartPos > 0) and (Value[StartPos] in
      ['A'..'Z', 'a'..'z']) do Dec(StartPos);
    Inc(StartPos);
    EndPos := SchemePos + 3;
    while (EndPos <= Length(Value)) and
      not (Value[EndPos] in [' ', '"', '''', #9, #10, #13]) do Inc(EndPos);
    Result := Copy(Value, StartPos, EndPos - StartPos);
  end
  else if Pos('.', Value) > 0 then
    Result := 'https://' + Trim(Value);
end;

end.
