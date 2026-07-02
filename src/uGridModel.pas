unit uGridModel;

{$mode delphi}{$H+}

interface

uses SysUtils, uCsvModel;

type
  TIntArray = array of Integer;
  TUnicodeStringArray = array of UnicodeString;

  TCsvGridModel = class
  private
    FDocument: TCsvDocument;
    FHeaderRow: Boolean;
    FCaseSensitive: Boolean;
    FFilters: TUnicodeStringArray;
    FVisibleRows: TIntArray;
    FSortColumn: Integer;
    FSortDirection: Integer;
    function SourceCellText(SourceRow, Column: Integer): UnicodeString;
    function MatchesFilter(const Value, Filter: UnicodeString): Boolean;
    function CompareRows(LeftRow, RightRow: Integer): Integer;
    procedure StableSort;
    procedure SetCaseSensitive(Value: Boolean);
  public
    constructor Create(ADocument: TCsvDocument; AHeaderRow: Boolean);
    procedure Rebuild;
    procedure SetFilter(Column: Integer; const Value: UnicodeString);
    procedure SetSort(Column, Direction: Integer);
    function HeaderText(Column: Integer): UnicodeString;
    function CellText(VisibleRow, Column: Integer): UnicodeString;
    function SourceRowAt(VisibleRow: Integer): Integer;
    function VisibleCount: Integer;
    property CaseSensitive: Boolean read FCaseSensitive write SetCaseSensitive;
    property SortColumn: Integer read FSortColumn;
    property SortDirection: Integer read FSortDirection;
  end;

implementation

uses uNaturalSort;

constructor TCsvGridModel.Create(ADocument: TCsvDocument; AHeaderRow: Boolean);
begin
  inherited Create;
  FDocument := ADocument;
  FHeaderRow := AHeaderRow;
  FSortColumn := -1;
  FSortDirection := 0;
  if Assigned(FDocument) then
    SetLength(FFilters, FDocument.ColumnCount);
  Rebuild;
end;

function TCsvGridModel.SourceCellText(SourceRow, Column: Integer): UnicodeString;
begin
  Result := '';
  if not Assigned(FDocument) or (SourceRow < 0) or
    (SourceRow >= FDocument.RowCount) or (Column < 0) or
    (Column >= Length(FDocument.Rows[SourceRow].Cells)) then Exit;
  Result := FDocument.CellValue(SourceRow, Column);
end;

function TCsvGridModel.HeaderText(Column: Integer): UnicodeString;
begin
  if FHeaderRow and Assigned(FDocument) and (FDocument.RowCount > 0) then
    Result := SourceCellText(0, Column)
  else
    Result := '';
  if Result = '' then Result := UnicodeString(Format('Column %d', [Column + 1]));
end;

function TCsvGridModel.MatchesFilter(const Value, Filter: UnicodeString): Boolean;
var
  Needle, Haystack: UnicodeString;
  ValueNumber, FilterNumber: Double;
  FS: TFormatSettings;
begin
  if Filter = '' then Exit(True);
  Haystack := Value;
  Needle := Filter;
  if not FCaseSensitive then
  begin
    Haystack := UnicodeLowerCase(Haystack);
    Needle := UnicodeLowerCase(Needle);
  end;

  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if (Length(Needle) > 1) and (Needle[1] in ['<', '>']) and
    TryStrToFloat(UTF8Encode(Copy(Needle, 2, MaxInt)), FilterNumber, FS) and
    TryStrToFloat(UTF8Encode(Haystack), ValueNumber, FS) then
  begin
    if Needle[1] = '<' then Exit(ValueNumber < FilterNumber);
    Exit(ValueNumber > FilterNumber);
  end;

  if Length(Needle) > 1 then
    case Needle[1] of
      '=': Exit(Haystack = Copy(Needle, 2, MaxInt));
      '!': Exit(Pos(Copy(Needle, 2, MaxInt), Haystack) = 0);
      '<': Exit(Haystack < Copy(Needle, 2, MaxInt));
      '>': Exit(Haystack > Copy(Needle, 2, MaxInt));
    end;
  Result := Pos(Needle, Haystack) > 0;
end;

function TCsvGridModel.CompareRows(LeftRow, RightRow: Integer): Integer;
begin
  Result := NaturalCompare(SourceCellText(LeftRow, FSortColumn),
    SourceCellText(RightRow, FSortColumn));
  if (Result <> 0) and (FSortDirection < 0) then Result := -Result;
  if Result = 0 then
  begin
    if LeftRow < RightRow then Result := -1
    else if LeftRow > RightRow then Result := 1;
  end;
end;

procedure TCsvGridModel.StableSort;
var
  Temp: TIntArray;

  procedure Merge(First, Middle, Last: Integer);
  var
    Left, Right, OutPos, I: Integer;
  begin
    Left := First;
    Right := Middle + 1;
    OutPos := First;
    while (Left <= Middle) and (Right <= Last) do
    begin
      if CompareRows(FVisibleRows[Left], FVisibleRows[Right]) <= 0 then
      begin
        Temp[OutPos] := FVisibleRows[Left];
        Inc(Left);
      end
      else
      begin
        Temp[OutPos] := FVisibleRows[Right];
        Inc(Right);
      end;
      Inc(OutPos);
    end;
    while Left <= Middle do
    begin
      Temp[OutPos] := FVisibleRows[Left];
      Inc(Left);
      Inc(OutPos);
    end;
    while Right <= Last do
    begin
      Temp[OutPos] := FVisibleRows[Right];
      Inc(Right);
      Inc(OutPos);
    end;
    for I := First to Last do FVisibleRows[I] := Temp[I];
  end;

  procedure Sort(First, Last: Integer);
  var
    Middle: Integer;
  begin
    if First >= Last then Exit;
    Middle := (First + Last) div 2;
    Sort(First, Middle);
    Sort(Middle + 1, Last);
    Merge(First, Middle, Last);
  end;

begin
  if Length(FVisibleRows) < 2 then Exit;
  SetLength(Temp, Length(FVisibleRows));
  Sort(0, High(FVisibleRows));
end;

procedure TCsvGridModel.Rebuild;
var
  SourceRow, Column, N, FirstRow: Integer;
  IncludeRow: Boolean;
begin
  SetLength(FVisibleRows, 0);
  if not Assigned(FDocument) then Exit;
  FirstRow := Ord(FHeaderRow and (FDocument.RowCount > 0));
  SetLength(FVisibleRows, FDocument.RowCount - FirstRow);
  N := 0;
  for SourceRow := FirstRow to FDocument.RowCount - 1 do
  begin
    IncludeRow := True;
    for Column := 0 to High(FFilters) do
      if (FFilters[Column] <> '') and
        not MatchesFilter(SourceCellText(SourceRow, Column), FFilters[Column]) then
      begin
        IncludeRow := False;
        Break;
      end;
    if IncludeRow then
    begin
      FVisibleRows[N] := SourceRow;
      Inc(N);
    end;
  end;
  if N <> Length(FVisibleRows) then SetLength(FVisibleRows, N);
  if (FSortColumn >= 0) and (FSortDirection <> 0) then StableSort;
end;

procedure TCsvGridModel.SetFilter(Column: Integer; const Value: UnicodeString);
begin
  if (Column < 0) or (Column >= Length(FFilters)) then Exit;
  FFilters[Column] := Value;
  Rebuild;
end;

procedure TCsvGridModel.SetCaseSensitive(Value: Boolean);
begin
  if FCaseSensitive = Value then Exit;
  FCaseSensitive := Value;
  Rebuild;
end;

procedure TCsvGridModel.SetSort(Column, Direction: Integer);
begin
  if not Assigned(FDocument) or (Column < 0) or
    (Column >= FDocument.ColumnCount) or (Direction = 0) then
  begin
    FSortColumn := -1;
    FSortDirection := 0;
  end
  else
  begin
    FSortColumn := Column;
    if Direction < 0 then FSortDirection := -1 else FSortDirection := 1;
  end;
  Rebuild;
end;

function TCsvGridModel.CellText(VisibleRow, Column: Integer): UnicodeString;
begin
  Result := SourceCellText(SourceRowAt(VisibleRow), Column);
end;

function TCsvGridModel.SourceRowAt(VisibleRow: Integer): Integer;
begin
  if (VisibleRow < 0) or (VisibleRow >= Length(FVisibleRows)) then Exit(-1);
  Result := FVisibleRows[VisibleRow];
end;

function TCsvGridModel.VisibleCount: Integer;
begin
  Result := Length(FVisibleRows);
end;

end.
