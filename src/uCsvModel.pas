unit uCsvModel;

{$mode delphi}{$H+}

interface

uses Windows, SysUtils, Classes;

type
  TCsvEncodingInfo = record
    Name: UnicodeString;
    HasBom: Boolean;
  end;

  TCsvCell = record
    Value: UnicodeString;
    Lexeme: UnicodeString;
    SourceStart: Integer;
    SourceLength: Integer;
    Quoted: Boolean;
    ValueReady: Boolean;
  end;

  TCsvCellArray = array of TCsvCell;

  TCsvRow = record
    Cells: TCsvCellArray;
    SourceStart: Integer;
    SourceLength: Integer;
    IsComment: Boolean;
  end;

  TCsvRowArray = array of TCsvRow;

  TCsvDocument = class
  private
    FRows: TCsvRowArray;
    FSourceText: UnicodeString;
    FDelimiter: WideChar;
    FEncoding: TCsvEncodingInfo;
    FMaxColumns: Integer;
    FRowCount: Integer;
    FHiddenCommentCount: Integer;
    FTrimValues: Boolean;
    FNextDecodeRow: Integer;
    FNextDecodeColumn: Integer;
    procedure AddRow(const Cells: TCsvCellArray; StartPos, SourceLength: Integer;
      IsComment: Boolean);
    procedure EnsureCellValue(Row, Column: Integer);
  public
    function Parse(const Source: UnicodeString; Delimiter: WideChar;
      SkipComments: Integer; TrimValues: Boolean = True;
      MaxColumnSamples: Integer = 1000): Boolean;
    function RowCount: Integer;
    function ColumnCount: Integer;
    function CellValue(Row, Column: Integer): UnicodeString;
    procedure PredecodeSampleValues(MaxSamples: Integer);
    function DecodePendingValues(MaxCells: Integer): Integer;
    function HasPendingValues: Boolean;
    function ApplyCellEdit(Row, Column: Integer; const Value: UnicodeString): Boolean;
    function InsertRowAfter(Row: Integer): Boolean;
    function DeleteRow(Row: Integer): Boolean;
    function DeleteColumn(Column: Integer): Boolean;
    property Rows: TCsvRowArray read FRows;
    property SourceText: UnicodeString read FSourceText;
    property Delimiter: WideChar read FDelimiter;
    property Encoding: TCsvEncodingInfo read FEncoding write FEncoding;
    property HiddenCommentCount: Integer read FHiddenCommentCount;
  end;

function LoadCsvFile(const FileName: UnicodeString; MaxSize: Int64;
  Delimiter: WideChar; SkipComments: Integer; out Doc: TCsvDocument;
  TrimValues: Boolean = True; MaxColumnSamples: Integer = 1000): Boolean;
function LoadCsvFileAs(const FileName: UnicodeString; MaxSize: Int64;
  Delimiter: WideChar; SkipComments: Integer; const EncodingName: UnicodeString;
  out Doc: TCsvDocument; TrimValues: Boolean = True;
  MaxColumnSamples: Integer = 1000): Boolean;
function DetectCsvDelimiter(const Source: UnicodeString): WideChar;
function LastCsvLoadError: UnicodeString;

implementation

var
  GLastLoadError: UnicodeString;

function FormatBytes(Size: Int64): UnicodeString;
begin
  if Size >= 1024 * 1024 then
    Result := UnicodeString(Format('%d bytes (%.1f MB)', [Size, Size / (1024 * 1024)]))
  else if Size >= 1024 then
    Result := UnicodeString(Format('%d bytes (%.1f KB)', [Size, Size / 1024]))
  else
    Result := UnicodeString(Format('%d bytes', [Size]));
end;

function LastCsvLoadError: UnicodeString;
begin
  Result := GLastLoadError;
end;

function IsSingleSemicolonCommentRowAt(const Source: UnicodeString;
  StartPos: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (StartPos > Length(Source)) or (Source[StartPos] <> ';') then Exit;
  I := StartPos + 1;
  while (I <= Length(Source)) and not (Source[I] in [#10, #13]) do
  begin
    if Source[I] = ';' then Exit;
    Inc(I);
  end;
  Result := True;
end;

function IsCsvCommentRowAt(const Source: UnicodeString; StartPos: Integer): Boolean;
begin
  Result := (StartPos <= Length(Source)) and
    ((Source[StartPos] = '#') or IsSingleSemicolonCommentRowAt(Source, StartPos) or
    ((StartPos + 3 <= Length(Source)) and
    (UpCase(Source[StartPos]) = 'S') and
    (UpCase(Source[StartPos + 1]) = 'E') and
    (UpCase(Source[StartPos + 2]) = 'P') and
    (Source[StartPos + 3] = '=')));
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

function DecodeBytes(const B: TBytes; const ForcedEncoding: UnicodeString;
  out Enc: TCsvEncodingInfo): UnicodeString;
var
  I, Start, Count: Integer;
  A: AnsiString;
begin
  Enc.HasBom := False;
  Start := 0;
  if ForcedEncoding <> '' then
  begin
    Enc.Name := ForcedEncoding;
    if SameText(Enc.Name, 'UTF-8') and (Length(B) >= 3) and
      (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF) then
    begin
      Enc.HasBom := True;
      Start := 3;
    end
    else if SameText(Enc.Name, 'UTF-16LE') and (Length(B) >= 2) and
      (B[0] = $FF) and (B[1] = $FE) then
    begin
      Enc.HasBom := True;
      Start := 2;
    end
    else if SameText(Enc.Name, 'UTF-16BE') and (Length(B) >= 2) and
      (B[0] = $FE) and (B[1] = $FF) then
    begin
      Enc.HasBom := True;
      Start := 2;
    end;
  end
  else if (Length(B) >= 3) and (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF) then
  begin
    Enc.Name := 'UTF-8';
    Enc.HasBom := True;
    Start := 3;
  end
  else if (Length(B) >= 2) and (B[0] = $FF) and (B[1] = $FE) then
  begin
    Enc.Name := 'UTF-16LE';
    Enc.HasBom := True;
    Start := 2;
  end
  else if (Length(B) >= 2) and (B[0] = $FE) and (B[1] = $FF) then
  begin
    Enc.Name := 'UTF-16BE';
    Enc.HasBom := True;
    Start := 2;
  end
  else if (Length(B) >= 2) and (B[0] = 0) and (B[1] <> 0) then
    Enc.Name := 'UTF-16BE'
  else if (Length(B) >= 2) and (B[1] = 0) and (B[0] <> 0) then
    Enc.Name := 'UTF-16LE'
  else if IsValidUtf8(B) then
    Enc.Name := 'UTF-8'
  else
    Enc.Name := 'ANSI';

  if (Enc.Name = 'UTF-16LE') or (Enc.Name = 'UTF-16BE') then
  begin
    SetLength(Result, (Length(B) - Start) div 2);
    for I := 1 to Length(Result) do
      if Enc.Name = 'UTF-16LE' then
        Result[I] := WideChar(B[Start + (I - 1) * 2] or
          (B[Start + (I - 1) * 2 + 1] shl 8))
      else
        Result[I] := WideChar((B[Start + (I - 1) * 2] shl 8) or
          B[Start + (I - 1) * 2 + 1]);
    Exit;
  end;

  if Length(B) > Start then
    SetString(A, PAnsiChar(@B[Start]), Length(B) - Start)
  else
    A := '';
  if Enc.Name = 'UTF-8' then Exit(UTF8Decode(A));
  Count := MultiByteToWideChar(CP_ACP, 0, PAnsiChar(A), Length(A), nil, 0);
  SetLength(Result, Count);
  if Count > 0 then
    MultiByteToWideChar(CP_ACP, 0, PAnsiChar(A), Length(A),
      PWideChar(Result), Count);
end;

function DetectCsvDelimiter(const Source: UnicodeString): WideChar;
const
  Candidates: array[0..4] of WideChar = (',', ';', '|', #9, ':');
  SampleRows = 5;
var
  Counts: array[0..SampleRows - 1, 0..4] of Integer;
  Scores: array[0..4] of Integer;
  I, J, K, Best, Row, RowTotal: Integer;
  InQuotes: Boolean;
begin
  FillChar(Counts, SizeOf(Counts), 0);
  I := 1;
  Row := 0;
  while (I <= Length(Source)) and (Row < SampleRows) do
  begin
    while (I <= Length(Source)) and (Source[I] in [#10, #13]) do Inc(I);
    if I > Length(Source) then Break;
    if IsCsvCommentRowAt(Source, I) then
    begin
      while (I <= Length(Source)) and not (Source[I] in [#10, #13]) do Inc(I);
      Continue;
    end;
    InQuotes := False;
    RowTotal := 0;
    while (I <= Length(Source)) and (InQuotes or not (Source[I] in [#10, #13])) do
    begin
      if Source[I] = '"' then
      begin
        if InQuotes and (I < Length(Source)) and (Source[I + 1] = '"') then Inc(I)
        else InQuotes := not InQuotes;
      end
      else if not InQuotes then
        for J := 0 to High(Candidates) do
          if Source[I] = Candidates[J] then
          begin
            Inc(Counts[Row, J]);
            Inc(RowTotal);
          end;
      Inc(I);
    end;
    while (I <= Length(Source)) and (Source[I] in [#10, #13]) do Inc(I);
    if RowTotal > 0 then Inc(Row);
  end;

  FillChar(Scores, SizeOf(Scores), 0);
  for J := 0 to High(Candidates) do
    for K := 0 to Row - 1 do
      for I := 0 to Row - 1 do
        if (Counts[K, J] > 0) and (Counts[K, J] = Counts[I, J]) then
          Inc(Scores[J], 10 + Counts[K, J])
        else if Counts[K, J] > 0 then
          Inc(Scores[J], 5);

  Best := 0;
  for J := 1 to High(Candidates) do
    if Scores[J] > Scores[Best] then Best := J;
  Result := Candidates[Best];
end;

function ScanCsvRowShape(const Source: UnicodeString; StartPos: Integer;
  Delimiter: WideChar; out NextPos, ColumnCount: Integer;
  out IsEmpty: Boolean): Boolean;
var
  I: Integer;
  InQuotes, HasContent: Boolean;
begin
  Result := False;
  NextPos := StartPos;
  ColumnCount := 0;
  IsEmpty := True;
  if StartPos > Length(Source) then Exit;
  I := StartPos;
  InQuotes := False;
  HasContent := False;
  ColumnCount := 1;
  while (I <= Length(Source)) and (InQuotes or not (Source[I] in [#10, #13])) do
  begin
    HasContent := True;
    if Source[I] = '"' then
    begin
      if InQuotes and (I < Length(Source)) and (Source[I + 1] = '"') then Inc(I)
      else InQuotes := not InQuotes;
    end
    else if not InQuotes and (Source[I] = Delimiter) then
      Inc(ColumnCount);
    Inc(I);
  end;
  IsEmpty := not HasContent;
  if (I <= Length(Source)) and (Source[I] = #13) and
    (I < Length(Source)) and (Source[I + 1] = #10) then Inc(I);
  if (I <= Length(Source)) and (Source[I] in [#10, #13]) then Inc(I);
  NextPos := I;
  Result := True;
end;

procedure AnalyzeCsvShape(const Source: UnicodeString; Delimiter: WideChar;
  MaxColumnSamples, SkipComments: Integer; out UsedColumns: Integer;
  out FirstFullRowStart, ExpectedRows, HiddenCommentCount: Integer);
var
  Starts, Counts, RowStarts: array of Integer;
  RowEmpty, RowComment: array of Boolean;
  I, NextPos, Columns, Samples, Best, SampleLimit, RowCount, Capacity,
    Row: Integer;
  Empty, IsComment, HasDataRow, SkipRow: Boolean;
begin
  UsedColumns := 0;
  FirstFullRowStart := 1;
  ExpectedRows := 0;
  HiddenCommentCount := 0;
  if Source = '' then Exit;
  SampleLimit := MaxColumnSamples;
  if SampleLimit < 0 then SampleLimit := 0;
  I := 1;
  Samples := 0;
  RowCount := 0;
  Capacity := 0;
  while I <= Length(Source) do
  begin
    if not ScanCsvRowShape(Source, I, Delimiter, NextPos, Columns, Empty) then Break;
    if RowCount >= Capacity then
    begin
      if Capacity = 0 then Capacity := 256 else Capacity := Capacity * 2;
      SetLength(RowStarts, Capacity);
      SetLength(RowEmpty, Capacity);
      SetLength(RowComment, Capacity);
    end;
    RowStarts[RowCount] := I;
    RowEmpty[RowCount] := Empty;
    RowComment[RowCount] := IsCsvCommentRowAt(Source, I);
    Inc(RowCount);

    if (Samples < SampleLimit) and (not Empty) and
      not RowComment[RowCount - 1] then
    begin
      SetLength(Starts, Samples + 1);
      SetLength(Counts, Samples + 1);
      Starts[Samples] := I;
      Counts[Samples] := Columns;
      if Columns > UsedColumns then UsedColumns := Columns;
      Inc(Samples);
    end;
    I := NextPos;
  end;
  if UsedColumns > 0 then
  begin
    Best := 0;
    while (Best < Samples) and (Counts[Best] < UsedColumns) do Inc(Best);
    if Best < Samples then FirstFullRowStart := Starts[Best];
  end;

  HasDataRow := False;
  for Row := 0 to RowCount - 1 do
  begin
    IsComment := RowComment[Row] or
      ((FirstFullRowStart > 1) and (RowStarts[Row] < FirstFullRowStart));
    SkipRow := ((SkipComments = 2) or
      ((SkipComments = 3) and not HasDataRow)) and
      (IsComment or RowEmpty[Row]);
    if SkipRow and IsComment then Inc(HiddenCommentCount);
    if not SkipRow then
    begin
      Inc(ExpectedRows);
      if not IsComment and not RowEmpty[Row] then HasDataRow := True;
    end;
  end;
end;

function TrimCsvValue(const Value: UnicodeString): UnicodeString;
var
  First, Last: Integer;
begin
  First := 1;
  Last := Length(Value);
  while (First <= Last) and (Value[First] in [' ', #9]) do Inc(First);
  while (Last >= First) and (Value[Last] in [' ', #9]) do Dec(Last);
  Result := Copy(Value, First, Last - First + 1);
end;

function DecodeCell(const Lexeme: UnicodeString; TrimValues: Boolean;
  out Quoted: Boolean): UnicodeString;
var
  I, J: Integer;
begin
  Quoted := (Length(Lexeme) >= 2) and (Lexeme[1] = '"') and
    (Lexeme[Length(Lexeme)] = '"');
  if not Quoted then
  begin
    if TrimValues then Exit(TrimCsvValue(Lexeme));
    Exit(Lexeme);
  end;
  Result := Copy(Lexeme, 2, Length(Lexeme) - 2);
  I := 1;
  J := 1;
  while I <= Length(Result) do
  begin
    Result[J] := Result[I];
    if (Result[I] = '"') and (I < Length(Result)) and (Result[I + 1] = '"') then
      Inc(I);
    Inc(I);
    Inc(J);
  end;
  SetLength(Result, J - 1);
end;

procedure TCsvDocument.AddRow(const Cells: TCsvCellArray; StartPos,
  SourceLength: Integer; IsComment: Boolean);
var
  N: Integer;
begin
  N := FRowCount;
  if N >= Length(FRows) then SetLength(FRows, N + 1);
  Inc(FRowCount);
  FRows[N].Cells := Cells;
  FRows[N].SourceStart := StartPos;
  FRows[N].SourceLength := SourceLength;
  FRows[N].IsComment := IsComment;
  if Length(Cells) > FMaxColumns then FMaxColumns := Length(Cells);
end;

procedure TCsvDocument.EnsureCellValue(Row, Column: Integer);
var
  Cell: ^TCsvCell;
begin
  if (Row < 0) or (Row >= FRowCount) or (Column < 0) or
    (Column >= Length(FRows[Row].Cells)) then Exit;
  Cell := @FRows[Row].Cells[Column];
  if Cell^.ValueReady then Exit;
  Cell^.Value := DecodeCell(Cell^.Lexeme, FTrimValues, Cell^.Quoted);
  Cell^.ValueReady := True;
end;

function TCsvDocument.CellValue(Row, Column: Integer): UnicodeString;
begin
  Result := '';
  if (Row < 0) or (Row >= FRowCount) or (Column < 0) or
    (Column >= Length(FRows[Row].Cells)) then Exit;
  EnsureCellValue(Row, Column);
  Result := FRows[Row].Cells[Column].Value;
end;

procedure TCsvDocument.PredecodeSampleValues(MaxSamples: Integer);
var
  SampleCount, SampleNo, Row, Column: Integer;
begin
  if (FRowCount <= 0) or (MaxSamples <= 0) then Exit;
  if MaxSamples >= FRowCount then SampleCount := FRowCount
  else SampleCount := MaxSamples;
  for SampleNo := 0 to SampleCount - 1 do
  begin
    if SampleCount <= 1 then Row := 0
    else Row := Integer((Int64(SampleNo) * (FRowCount - 1)) div
      (SampleCount - 1));
    for Column := 0 to High(FRows[Row].Cells) do
      EnsureCellValue(Row, Column);
  end;
end;

function TCsvDocument.DecodePendingValues(MaxCells: Integer): Integer;
var
  Cell: ^TCsvCell;
begin
  Result := 0;
  if MaxCells <= 0 then Exit;
  while FNextDecodeRow < FRowCount do
  begin
    while FNextDecodeColumn < Length(FRows[FNextDecodeRow].Cells) do
    begin
      Cell := @FRows[FNextDecodeRow].Cells[FNextDecodeColumn];
      Inc(FNextDecodeColumn);
      if Cell^.ValueReady then Continue;
      Cell^.Value := DecodeCell(Cell^.Lexeme, FTrimValues, Cell^.Quoted);
      Cell^.ValueReady := True;
      Inc(Result);
      if Result >= MaxCells then Exit;
    end;
    Inc(FNextDecodeRow);
    FNextDecodeColumn := 0;
  end;
end;

function TCsvDocument.HasPendingValues: Boolean;
var
  Row, Column: Integer;
begin
  Result := False;
  Row := FNextDecodeRow;
  Column := FNextDecodeColumn;
  while Row < FRowCount do
  begin
    while Column < Length(FRows[Row].Cells) do
    begin
      if not FRows[Row].Cells[Column].ValueReady then Exit(True);
      Inc(Column);
    end;
    Inc(Row);
    Column := 0;
  end;
end;

function TCsvDocument.Parse(const Source: UnicodeString; Delimiter: WideChar;
  SkipComments: Integer; TrimValues: Boolean; MaxColumnSamples: Integer): Boolean;
var
  I, FieldStart, RowStart, N, CommentEnd, UsedColumns, FirstFullRowStart,
    ExpectedRows, HiddenCommentCount: Integer;
  InQuotes, IsComment, HasDataRow: Boolean;
  Cells: TCsvCellArray;
  Cell: TCsvCell;

  procedure AddCell(EndPos: Integer);
  begin
    if (UsedColumns > 0) and (Length(Cells) >= UsedColumns) then Exit;
    Cell.SourceStart := FieldStart;
    Cell.SourceLength := EndPos - FieldStart;
    Cell.Lexeme := Copy(Source, FieldStart, Cell.SourceLength);
    Cell.Value := '';
    Cell.Quoted := (Cell.SourceLength >= 2) and (Cell.Lexeme[1] = '"') and
      (Cell.Lexeme[Cell.SourceLength] = '"');
    Cell.ValueReady := False;
    N := Length(Cells);
    SetLength(Cells, N + 1);
    Cells[N] := Cell;
  end;

  procedure FinishRow(EndPos: Integer);
  var
    IsEmptyRow: Boolean;
  begin
    IsEmptyRow := (Length(Cells) = 1) and (Cells[0].SourceLength = 0);
    if ((SkipComments = 2) or
      ((SkipComments = 3) and not HasDataRow)) and (IsComment or IsEmptyRow) then
      SetLength(Cells, 0)
    else
    begin
      AddRow(Cells, RowStart, EndPos - RowStart, IsComment);
      if not IsComment and not IsEmptyRow then HasDataRow := True;
    end;
    SetLength(Cells, 0);
  end;

begin
  Result := False;
  FSourceText := Source;
  FDelimiter := Delimiter;
  SetLength(FRows, 0);
  FRowCount := 0;
  FMaxColumns := 0;
  FHiddenCommentCount := 0;
  FTrimValues := TrimValues;
  FNextDecodeRow := 0;
  FNextDecodeColumn := 0;
  if Delimiter = #0 then FDelimiter := DetectCsvDelimiter(Source);
  AnalyzeCsvShape(Source, FDelimiter, MaxColumnSamples, SkipComments,
    UsedColumns, FirstFullRowStart, ExpectedRows, HiddenCommentCount);
  FHiddenCommentCount := HiddenCommentCount;
  if Source = '' then Exit(True);
  if ExpectedRows > 0 then SetLength(FRows, ExpectedRows);

  I := 1;
  RowStart := 1;
  FieldStart := 1;
  InQuotes := False;
  HasDataRow := False;
  IsComment := IsCsvCommentRowAt(Source, 1) or
    ((FirstFullRowStart > 1) and (RowStart < FirstFullRowStart));
  while I <= Length(Source) do
  begin
    if (I = RowStart) and IsComment and
      ((SkipComments in [1, 2]) or ((SkipComments = 3) and not HasDataRow)) then
    begin
      CommentEnd := I;
      while (CommentEnd <= Length(Source)) and
        not (Source[CommentEnd] in [#10, #13]) do Inc(CommentEnd);
      if (SkipComments = 2) or ((SkipComments = 3) and not HasDataRow) then
      begin
        I := CommentEnd;
        if (I <= Length(Source)) and (Source[I] = #13) and
          (I < Length(Source)) and (Source[I + 1] = #10) then Inc(I);
        Inc(I);
        RowStart := I;
        FieldStart := I;
        SetLength(Cells, 0);
        if I <= Length(Source) then
          IsComment := IsCsvCommentRowAt(Source, I) or
            ((FirstFullRowStart > 1) and (RowStart < FirstFullRowStart));
        Continue;
      end;
      if SkipComments = 1 then
      begin
        FieldStart := RowStart;
        AddCell(CommentEnd);
      end;
      I := CommentEnd;
      if (I <= Length(Source)) and (Source[I] = #13) and
        (I < Length(Source)) and (Source[I + 1] = #10) then Inc(I);
      FinishRow(I + 1);
      Inc(I);
      RowStart := I;
      FieldStart := I;
      if I <= Length(Source) then
        IsComment := IsCsvCommentRowAt(Source, I) or
          ((FirstFullRowStart > 1) and (RowStart < FirstFullRowStart));
      Continue;
    end;
    if (Source[I] = '"') then
    begin
      if InQuotes and (I < Length(Source)) and (Source[I + 1] = '"') then Inc(I)
      else InQuotes := not InQuotes;
    end
    else if not InQuotes and (Source[I] = FDelimiter) then
    begin
      AddCell(I);
      FieldStart := I + 1;
    end
    else if not InQuotes and (Source[I] in [#10, #13]) then
    begin
      AddCell(I);
      if (Source[I] = #13) and (I < Length(Source)) and (Source[I + 1] = #10) then Inc(I);
      FinishRow(I + 1);
      Inc(I);
      RowStart := I;
      FieldStart := I;
      if I <= Length(Source) then
        IsComment := IsCsvCommentRowAt(Source, I) or
          ((FirstFullRowStart > 1) and (RowStart < FirstFullRowStart));
      Continue;
    end;
    Inc(I);
  end;
  if FieldStart <= Length(Source) then AddCell(Length(Source) + 1)
  else if (Length(Source) > 0) and (Source[Length(Source)] = FDelimiter) then AddCell(Length(Source) + 1);
  if (Length(Cells) > 0) or (RowStart <= Length(Source)) then
    FinishRow(Length(Source) + 1);
  if UsedColumns > 0 then FMaxColumns := UsedColumns;
  if FRowCount <> Length(FRows) then SetLength(FRows, FRowCount);
  PredecodeSampleValues(MaxColumnSamples);
  Result := not InQuotes;
end;

function TCsvDocument.RowCount: Integer;
begin
  Result := FRowCount;
end;

function TCsvDocument.ColumnCount: Integer;
begin
  Result := FMaxColumns;
end;

function EscapeCsvValue(const Value: UnicodeString): UnicodeString;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(Value) do
  begin
    Result := Result + Value[I];
    if Value[I] = '"' then Result := Result + '"';
  end;
end;

function TCsvDocument.ApplyCellEdit(Row, Column: Integer;
  const Value: UnicodeString): Boolean;
var
  Cell: ^TCsvCell;
  OldLength, Delta, R, C: Integer;
  Lexeme: UnicodeString;
  NeedsQuotes: Boolean;
begin
  Result := False;
  if (Row < 0) or (Row >= Length(FRows)) or (Column < 0) or
    (Column >= Length(FRows[Row].Cells)) or FRows[Row].IsComment then Exit;
  EnsureCellValue(Row, Column);
  Cell := @FRows[Row].Cells[Column];
  if Cell^.Value = Value then Exit(True);
  NeedsQuotes := Cell^.Quoted or (Pos(FDelimiter, Value) > 0) or
    (Pos('"', Value) > 0) or (Pos(#10, Value) > 0) or (Pos(#13, Value) > 0) or
    ((Value <> '') and ((Value[1] in [' ', #9]) or
    (Value[Length(Value)] in [' ', #9])));
  if NeedsQuotes then Lexeme := '"' + EscapeCsvValue(Value) + '"'
  else Lexeme := Value;

  OldLength := Cell^.SourceLength;
  Delta := Length(Lexeme) - OldLength;
  FSourceText := Copy(FSourceText, 1, Cell^.SourceStart - 1) + Lexeme +
    Copy(FSourceText, Cell^.SourceStart + OldLength, MaxInt);
  Cell^.Value := Value;
  Cell^.Lexeme := Lexeme;
  Cell^.SourceLength := Length(Lexeme);
  Cell^.Quoted := NeedsQuotes;
  Cell^.ValueReady := True;
  Inc(FRows[Row].SourceLength, Delta);

  if Delta <> 0 then
    for R := 0 to High(FRows) do
    begin
      if R > Row then Inc(FRows[R].SourceStart, Delta);
      for C := 0 to High(FRows[R].Cells) do
        if (R > Row) or ((R = Row) and (C > Column)) then
          Inc(FRows[R].Cells[C].SourceStart, Delta);
    end;
  Result := True;
end;

function TCsvDocument.InsertRowAfter(Row: Integer): Boolean;
var
  Column, ColumnCount, InsertAt, InsertLen, NewRowIndex, NewRowStart,
    NewRowLength, SourceEnd, R, C: Integer;
  Line, LineEnding, InsertText: UnicodeString;
  Cells: TCsvCellArray;
  HasTerminator: Boolean;

  function PreferredLineEnding: UnicodeString;
  var
    I: Integer;
  begin
    Result := #13#10;
    I := 1;
    while I <= Length(FSourceText) do
    begin
      if FSourceText[I] = #13 then
      begin
        if (I < Length(FSourceText)) and (FSourceText[I + 1] = #10) then
          Exit(#13#10);
        Exit(#13);
      end
      else if FSourceText[I] = #10 then
        Exit(#10);
      Inc(I);
    end;
  end;

  function RowLineEnding: UnicodeString;
  var
    LastPos: Integer;
  begin
    Result := PreferredLineEnding;
    if (Row < 0) or (Row >= FRowCount) then Exit;
    LastPos := FRows[Row].SourceStart + FRows[Row].SourceLength - 1;
    if (LastPos < 1) or (LastPos > Length(FSourceText)) then Exit;
    if FSourceText[LastPos] = #10 then
    begin
      if (LastPos > 1) and (FSourceText[LastPos - 1] = #13) then
        Exit(#13#10);
      Exit(#10);
    end;
    if FSourceText[LastPos] = #13 then Exit(#13);
  end;

begin
  Result := False;
  if (Row < 0) or (Row >= FRowCount) then Exit;
  ColumnCount := FMaxColumns;
  if ColumnCount < 1 then ColumnCount := 1;

  Line := '';
  for Column := 1 to ColumnCount - 1 do
    Line := Line + FDelimiter;
  LineEnding := RowLineEnding;

  InsertAt := FRows[Row].SourceStart + FRows[Row].SourceLength;
  SourceEnd := FRows[Row].SourceStart + FRows[Row].SourceLength - 1;
  HasTerminator := (SourceEnd >= 1) and (SourceEnd <= Length(FSourceText)) and
    (FSourceText[SourceEnd] in [#10, #13]);
  if HasTerminator then
  begin
    InsertText := Line + LineEnding;
    NewRowStart := InsertAt;
    NewRowLength := Length(InsertText);
  end
  else
  begin
    InsertText := LineEnding + Line;
    NewRowStart := InsertAt + Length(LineEnding);
    NewRowLength := Length(Line);
  end;
  InsertLen := Length(InsertText);
  if InsertLen <= 0 then Exit;

  FSourceText := Copy(FSourceText, 1, InsertAt - 1) + InsertText +
    Copy(FSourceText, InsertAt, MaxInt);

  for R := Row + 1 to High(FRows) do
  begin
    Inc(FRows[R].SourceStart, InsertLen);
    for C := 0 to High(FRows[R].Cells) do
      Inc(FRows[R].Cells[C].SourceStart, InsertLen);
  end;

  SetLength(Cells, ColumnCount);
  for Column := 0 to ColumnCount - 1 do
  begin
    Cells[Column].Value := '';
    Cells[Column].Lexeme := '';
    Cells[Column].SourceStart := NewRowStart + Column;
    Cells[Column].SourceLength := 0;
    Cells[Column].Quoted := False;
    Cells[Column].ValueReady := True;
  end;

  NewRowIndex := Row + 1;
  SetLength(FRows, Length(FRows) + 1);
  for R := High(FRows) downto NewRowIndex + 1 do
    FRows[R] := FRows[R - 1];
  FRows[NewRowIndex].Cells := Cells;
  FRows[NewRowIndex].SourceStart := NewRowStart;
  FRows[NewRowIndex].SourceLength := NewRowLength;
  FRows[NewRowIndex].IsComment := False;
  Inc(FRowCount);
  if FNextDecodeRow > Row then Inc(FNextDecodeRow);
  Result := True;
end;

function TCsvDocument.DeleteRow(Row: Integer): Boolean;
var
  Start, Len, R, C: Integer;
begin
  Result := False;
  if (Row < 0) or (Row >= Length(FRows)) then Exit;
  Start := FRows[Row].SourceStart;
  Len := FRows[Row].SourceLength;
  // Remove the row's slice (it spans the line including its terminator) from
  // the backing source text.
  FSourceText := Copy(FSourceText, 1, Start - 1) +
    Copy(FSourceText, Start + Len, MaxInt);
  // Shift the source offsets of all following rows/cells left by what we cut.
  for R := Row + 1 to High(FRows) do
  begin
    Dec(FRows[R].SourceStart, Len);
    for C := 0 to High(FRows[R].Cells) do
      Dec(FRows[R].Cells[C].SourceStart, Len);
  end;
  // Drop the row from the array, preserving order.
  for R := Row to High(FRows) - 1 do FRows[R] := FRows[R + 1];
  SetLength(FRows, Length(FRows) - 1);
  if FRowCount > 0 then Dec(FRowCount);
  if FNextDecodeRow > Row then Dec(FNextDecodeRow)
  else if FNextDecodeRow = Row then FNextDecodeColumn := 0;
  Result := True;
end;

function TCsvDocument.DeleteColumn(Column: Integer): Boolean;
var
  R, C, Start, Len, OldMaxColumns: Integer;

  procedure DeleteSourceSlice(SliceStart, SliceLength: Integer);
  var
    RR, CC: Integer;
  begin
    if SliceLength <= 0 then Exit;
    FSourceText := Copy(FSourceText, 1, SliceStart - 1) +
      Copy(FSourceText, SliceStart + SliceLength, MaxInt);
    for RR := 0 to High(FRows) do
    begin
      if FRows[RR].SourceStart > SliceStart then
        Dec(FRows[RR].SourceStart, SliceLength)
      else if FRows[RR].SourceStart + FRows[RR].SourceLength > SliceStart then
        Dec(FRows[RR].SourceLength, SliceLength);
      for CC := 0 to High(FRows[RR].Cells) do
        if FRows[RR].Cells[CC].SourceStart > SliceStart then
          Dec(FRows[RR].Cells[CC].SourceStart, SliceLength);
    end;
  end;

begin
  Result := False;
  if (Column < 0) or (Column >= FMaxColumns) then Exit;
  OldMaxColumns := FMaxColumns;
  for R := 0 to High(FRows) do
  begin
    if FRows[R].IsComment or (Column >= Length(FRows[R].Cells)) then Continue;
    if Length(FRows[R].Cells) = 1 then
    begin
      Start := FRows[R].Cells[Column].SourceStart;
      Len := FRows[R].Cells[Column].SourceLength;
    end
    else if Column < High(FRows[R].Cells) then
    begin
      Start := FRows[R].Cells[Column].SourceStart;
      Len := FRows[R].Cells[Column + 1].SourceStart - Start;
    end
    else
    begin
      Start := FRows[R].Cells[Column - 1].SourceStart +
        FRows[R].Cells[Column - 1].SourceLength;
      Len := FRows[R].Cells[Column].SourceStart +
        FRows[R].Cells[Column].SourceLength - Start;
    end;
    DeleteSourceSlice(Start, Len);
    for C := Column to High(FRows[R].Cells) - 1 do
      FRows[R].Cells[C] := FRows[R].Cells[C + 1];
    SetLength(FRows[R].Cells, Length(FRows[R].Cells) - 1);
    Result := True;
  end;
  if Result and (Column < OldMaxColumns) then
    FMaxColumns := OldMaxColumns - 1;
  FNextDecodeRow := 0;
  FNextDecodeColumn := 0;
end;

function LoadCsvFileAs(const FileName: UnicodeString; MaxSize: Int64;
  Delimiter: WideChar; SkipComments: Integer; const EncodingName: UnicodeString;
  out Doc: TCsvDocument; TrimValues: Boolean; MaxColumnSamples: Integer): Boolean;
var
  F: TFileStream;
  B: TBytes;
  Enc: TCsvEncodingInfo;
  Source: UnicodeString;
begin
  Doc := nil;
  Result := False;
  GLastLoadError := '';
  try
    F := TFileStream.Create(UTF8Encode(FileName), fmOpenRead or fmShareDenyNone);
    try
      if (MaxSize > 0) and (F.Size > MaxSize) then
      begin
        GLastLoadError := 'The file could not be loaded because it exceeds the configured size limit.' +
          #13#10 + 'File size: ' + FormatBytes(F.Size) +
          #13#10 + 'Limit: ' + FormatBytes(MaxSize);
        Exit;
      end;
      SetLength(B, F.Size);
      if F.Size > 0 then F.ReadBuffer(B[0], F.Size);
    finally
      F.Free;
    end;
    Source := DecodeBytes(B, EncodingName, Enc);
    Doc := TCsvDocument.Create;
    Doc.Encoding := Enc;
    Result := Doc.Parse(Source, Delimiter, SkipComments, TrimValues,
      MaxColumnSamples);
    if not Result then FreeAndNil(Doc);
  except
    FreeAndNil(Doc);
  end;
end;

function LoadCsvFile(const FileName: UnicodeString; MaxSize: Int64;
  Delimiter: WideChar; SkipComments: Integer; out Doc: TCsvDocument;
  TrimValues: Boolean; MaxColumnSamples: Integer): Boolean;
begin
  Result := LoadCsvFileAs(FileName, MaxSize, Delimiter, SkipComments, '', Doc,
    TrimValues, MaxColumnSamples);
end;

end.
