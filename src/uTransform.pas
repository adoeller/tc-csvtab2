unit uTransform;

{$mode delphi}{$H+}

interface

uses SysUtils, Classes, uCsvModel;

type
  TTransformConfig = class
  private
    FInitialHeaders: TStringList;
    FTargetOrder: TStringList;
    FConstants: TStringList;
    FFills: TStringList;
    FEnumerations: TStringList;
    FRenames: TStringList;
    FAddedHeaders: TStringList;
    FExportDelimiter: WideChar;
    FNumberFormat: UnicodeString;
    function MapValue(Map: TStringList; const Name: UnicodeString): UnicodeString;
  public
    function HeaderIndex(const Name: UnicodeString): Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Initialize(Document: TCsvDocument; HeaderRow: Boolean);
    function LoadJson(const FileName: UnicodeString): Boolean;
    function SaveJson(const FileName: UnicodeString): Boolean;
    function ExportCsv(const FileName: UnicodeString; Document: TCsvDocument;
      HeaderRow: Boolean): Boolean;
    procedure MoveColumn(Index, Delta: Integer);
    procedure AddColumn(Index: Integer; const Name: UnicodeString);
    procedure RemoveColumn(Index: Integer);
    procedure RenameColumn(Index: Integer; const NewName: UnicodeString);
    procedure SetConstant(Index: Integer; const Value: UnicodeString);
    procedure SetFill(Index: Integer; const Value: UnicodeString);
    procedure SetEnumeration(Index, StartValue, StopValue: Integer);
    function DisplayName(Index: Integer): UnicodeString;
    function TransformedColumnCount: Integer;
    function TransformedHeader(Col: Integer): UnicodeString;
    function TransformedCellValue(Col, SourceRow, DataStart: Integer;
      Document: TCsvDocument): UnicodeString;
    property TargetOrder: TStringList read FTargetOrder;
    property ExportDelimiter: WideChar read FExportDelimiter write FExportDelimiter;
    property NumberFormat: UnicodeString read FNumberFormat write FNumberFormat;
  end;

implementation

uses fpjson, jsonparser;

function JsonString(const S: UnicodeString): TJSONString;
begin
  Result := TJSONString.Create(UTF8Encode(S));
end;

procedure ReadStringArray(Obj: TJSONObject; const Name: String; List: TStringList);
var
  A: TJSONArray;
  I: Integer;
begin
  List.Clear;
  A := Obj.Arrays[Name];
  if not Assigned(A) then Exit;
  for I := 0 to A.Count - 1 do List.Add(UTF8Decode(A.Strings[I]));
end;

procedure ReadStringMap(Obj: TJSONObject; const Name: String; List: TStringList);
var
  Map: TJSONObject;
  I: Integer;
begin
  List.Clear;
  Map := Obj.Objects[Name];
  if not Assigned(Map) then Exit;
  for I := 0 to Map.Count - 1 do
    List.Values[UTF8Decode(Map.Names[I])] := UTF8Decode(Map.Items[I].AsString);
end;

function StringArray(List: TStringList): TJSONArray;
var
  I: Integer;
begin
  Result := TJSONArray.Create;
  for I := 0 to List.Count - 1 do Result.Add(JsonString(List[I]));
end;

function StringMap(List: TStringList): TJSONObject;
var
  I: Integer;
begin
  Result := TJSONObject.Create;
  for I := 0 to List.Count - 1 do
    Result.Add(UTF8Encode(List.Names[I]), JsonString(List.ValueFromIndex[I]));
end;

constructor TTransformConfig.Create;
begin
  inherited Create;
  FInitialHeaders := TStringList.Create;
  FTargetOrder := TStringList.Create;
  FConstants := TStringList.Create;
  FFills := TStringList.Create;
  FEnumerations := TStringList.Create;
  FRenames := TStringList.Create;
  FAddedHeaders := TStringList.Create;
  FExportDelimiter := ';';
  FNumberFormat := 'original';
end;

destructor TTransformConfig.Destroy;
begin
  FAddedHeaders.Free;
  FRenames.Free;
  FEnumerations.Free;
  FFills.Free;
  FConstants.Free;
  FTargetOrder.Free;
  FInitialHeaders.Free;
  inherited Destroy;
end;

procedure TTransformConfig.Initialize(Document: TCsvDocument; HeaderRow: Boolean);
var
  I: Integer;
  Name: UnicodeString;
begin
  FInitialHeaders.Clear;
  FTargetOrder.Clear;
  FConstants.Clear;
  FFills.Clear;
  FEnumerations.Clear;
  FRenames.Clear;
  FAddedHeaders.Clear;
  if not Assigned(Document) then Exit;
  for I := 0 to Document.ColumnCount - 1 do
  begin
    Name := '';
    if HeaderRow and (Document.RowCount > 0) and
      (I < Length(Document.Rows[0].Cells)) then Name := Document.CellValue(0, I);
    if Name = '' then Name := UnicodeString(Format('Column %d', [I + 1]));
    FInitialHeaders.Add(Name);
    FTargetOrder.Add(Name);
  end;
  FExportDelimiter := Document.Delimiter;
end;

function TTransformConfig.HeaderIndex(const Name: UnicodeString): Integer;
begin
  Result := FInitialHeaders.IndexOf(Name);
end;

function TTransformConfig.MapValue(Map: TStringList;
  const Name: UnicodeString): UnicodeString;
begin
  Result := Map.Values[Name];
end;

function TTransformConfig.LoadJson(const FileName: UnicodeString): Boolean;
var
  Stream: TFileStream;
  Parser: TJSONParser;
  Root: TJSONData;
  Obj, EnumObj, Range: TJSONObject;
  I: Integer;
  Delimiter: UnicodeString;
begin
  Result := False;
  Root := nil;
  try
    Stream := TFileStream.Create(UTF8Encode(FileName), fmOpenRead or fmShareDenyWrite);
    try
      Parser := TJSONParser.Create(Stream);
      try
        Root := Parser.Parse;
      finally
        Parser.Free;
      end;
      if Root.JSONType <> jtObject then Exit;
      Obj := TJSONObject(Root);
      ReadStringArray(Obj, 'initial_headers', FInitialHeaders);
      ReadStringArray(Obj, 'target_order', FTargetOrder);
      ReadStringMap(Obj, 'constant_vars', FConstants);
      ReadStringMap(Obj, 'fill_vars', FFills);
      ReadStringMap(Obj, 'rename_headers', FRenames);
      ReadStringArray(Obj, 'added_headers', FAddedHeaders);
      FEnumerations.Clear;
      EnumObj := Obj.Objects['enumeration_vars'];
      if Assigned(EnumObj) then
        for I := 0 to EnumObj.Count - 1 do
        begin
          Range := TJSONObject(EnumObj.Items[I]);
          FEnumerations.Values[UTF8Decode(EnumObj.Names[I])] :=
            IntToStr(Range.Get('start', 1)) + ':' + IntToStr(Range.Get('stop', 1));
        end;
      Delimiter := UTF8Decode(Obj.Get('export_delimiter', UTF8Encode(';')));
      if Delimiter <> '' then FExportDelimiter := Delimiter[1];
      FNumberFormat := UTF8Decode(Obj.Get('number_format', UTF8Encode('original')));
      Result := FTargetOrder.Count > 0;
    finally
      Root.Free;
      Stream.Free;
    end;
  except
    Result := False;
  end;
end;

function TTransformConfig.SaveJson(const FileName: UnicodeString): Boolean;
var
  Obj, Enums, Range: TJSONObject;
  I, P, StartValue, StopValue: Integer;
  Text: UTF8String;
  Stream: TFileStream;
begin
  Result := False;
  Obj := TJSONObject.Create;
  try
    Obj.Add('initial_headers', StringArray(FInitialHeaders));
    Obj.Add('target_order', StringArray(FTargetOrder));
    Obj.Add('constant_vars', StringMap(FConstants));
    Obj.Add('fill_vars', StringMap(FFills));
    Enums := TJSONObject.Create;
    for I := 0 to FEnumerations.Count - 1 do
    begin
      P := Pos(':', FEnumerations.ValueFromIndex[I]);
      StartValue := StrToIntDef(Copy(FEnumerations.ValueFromIndex[I], 1, P - 1), 1);
      StopValue := StrToIntDef(Copy(FEnumerations.ValueFromIndex[I], P + 1, MaxInt), StartValue);
      Range := TJSONObject.Create;
      Range.Add('start', StartValue);
      Range.Add('stop', StopValue);
      Enums.Add(UTF8Encode(FEnumerations.Names[I]), Range);
    end;
    Obj.Add('enumeration_vars', Enums);
    Obj.Add('rename_headers', StringMap(FRenames));
    Obj.Add('added_headers', StringArray(FAddedHeaders));
    Obj.Add('export_delimiter', JsonString(FExportDelimiter));
    Obj.Add('number_format', JsonString(FNumberFormat));
    Text := Obj.FormatJSON;
    Stream := TFileStream.Create(UTF8Encode(FileName), fmCreate);
    try
      if Length(Text) > 0 then Stream.WriteBuffer(PAnsiChar(Text)^, Length(Text));
    finally
      Stream.Free;
    end;
    Result := True;
  finally
    Obj.Free;
  end;
end;

function QuoteCsv(const Value: UnicodeString; Delimiter: WideChar): UnicodeString;
begin
  Result := Value;
  if (Pos(Delimiter, Result) > 0) or (Pos('"', Result) > 0) or
    (Pos(#10, Result) > 0) or (Pos(#13, Result) > 0) then
    Result := '"' + StringReplace(Result, '"', '""', [rfReplaceAll]) + '"';
end;

function IsDecimalText(const Value: UnicodeString): Boolean;
var
  I, Separators: Integer;
begin
  Result := False;
  if Value = '' then Exit;
  Separators := 0;
  for I := 1 to Length(Value) do
    if Value[I] in ['.', ','] then Inc(Separators)
    else if not (Value[I] in ['0'..'9']) then Exit;
  Result := Separators = 1;
end;

function TTransformConfig.ExportCsv(const FileName: UnicodeString;
  Document: TCsvDocument; HeaderRow: Boolean): Boolean;
var
  Output: TStringList;
  Row, Col, SourceCol, DataStart, P, StartValue, StopValue: Integer;
  Name, Value, EnumText, Line: UnicodeString;
  U: UTF8String;
  Stream: TFileStream;
begin
  Result := False;
  if not Assigned(Document) then Exit;
  Output := TStringList.Create;
  try
    Line := '';
    for Col := 0 to FTargetOrder.Count - 1 do
    begin
      if Col > 0 then Line := Line + FExportDelimiter;
      Name := FTargetOrder[Col];
      Value := MapValue(FRenames, Name);
      if Value = '' then Value := Name;
      Line := Line + QuoteCsv(Value, FExportDelimiter);
    end;
    Output.Add(Line);
    DataStart := Ord(HeaderRow);
    for Row := DataStart to Document.RowCount - 1 do
    begin
      Line := '';
      for Col := 0 to FTargetOrder.Count - 1 do
      begin
        if Col > 0 then Line := Line + FExportDelimiter;
        Name := FTargetOrder[Col];
        SourceCol := HeaderIndex(Name);
        Value := '';
        if (SourceCol >= 0) and (SourceCol < Length(Document.Rows[Row].Cells)) then
          Value := Document.CellValue(Row, SourceCol);
        if (Value = '') and (MapValue(FFills, Name) <> '') then Value := MapValue(FFills, Name);
        if MapValue(FConstants, Name) <> '' then Value := MapValue(FConstants, Name);
        EnumText := MapValue(FEnumerations, Name);
        if EnumText <> '' then
        begin
          P := Pos(':', EnumText);
          StartValue := StrToIntDef(Copy(EnumText, 1, P - 1), 1);
          StopValue := StrToIntDef(Copy(EnumText, P + 1, MaxInt), StartValue);
          if StartValue + Row - DataStart <= StopValue then
            Value := IntToStr(StartValue + Row - DataStart)
          else Value := '';
        end;
        if IsDecimalText(Value) and (FNumberFormat = '.') and (Pos(',', Value) > 0) then
          Value := StringReplace(Value, ',', '.', [])
        else if IsDecimalText(Value) and (FNumberFormat = ',') and (Pos('.', Value) > 0) then
          Value := StringReplace(Value, '.', ',', []);
        Line := Line + QuoteCsv(Value, FExportDelimiter);
      end;
      Output.Add(Line);
    end;
    U := UTF8Encode(Output.Text);
    Stream := TFileStream.Create(UTF8Encode(FileName), fmCreate);
    try
      if Length(U) > 0 then Stream.WriteBuffer(PAnsiChar(U)^, Length(U));
    finally
      Stream.Free;
    end;
    Result := True;
  finally
    Output.Free;
  end;
end;

procedure TTransformConfig.MoveColumn(Index, Delta: Integer);
begin
  if (Index < 0) or (Index >= FTargetOrder.Count) or
    (Index + Delta < 0) or (Index + Delta >= FTargetOrder.Count) then Exit;
  FTargetOrder.Move(Index, Index + Delta);
end;

procedure TTransformConfig.AddColumn(Index: Integer; const Name: UnicodeString);
begin
  if (Name = '') or (FTargetOrder.IndexOf(Name) >= 0) then Exit;
  if Index < 0 then Index := FTargetOrder.Count;
  FTargetOrder.Insert(Index, Name);
  FAddedHeaders.Add(Name);
end;

procedure TTransformConfig.RemoveColumn(Index: Integer);
begin
  if (Index >= 0) and (Index < FTargetOrder.Count) then FTargetOrder.Delete(Index);
end;

procedure TTransformConfig.RenameColumn(Index: Integer; const NewName: UnicodeString);
begin
  if (Index >= 0) and (Index < FTargetOrder.Count) and (NewName <> '') then
    FRenames.Values[FTargetOrder[Index]] := NewName;
end;

procedure TTransformConfig.SetConstant(Index: Integer; const Value: UnicodeString);
begin
  if (Index >= 0) and (Index < FTargetOrder.Count) then
    FConstants.Values[FTargetOrder[Index]] := Value;
end;

procedure TTransformConfig.SetFill(Index: Integer; const Value: UnicodeString);
begin
  if (Index >= 0) and (Index < FTargetOrder.Count) then
    FFills.Values[FTargetOrder[Index]] := Value;
end;

procedure TTransformConfig.SetEnumeration(Index, StartValue, StopValue: Integer);
begin
  if (Index >= 0) and (Index < FTargetOrder.Count) then
    FEnumerations.Values[FTargetOrder[Index]] := IntToStr(StartValue) + ':' + IntToStr(StopValue);
end;

function TTransformConfig.DisplayName(Index: Integer): UnicodeString;
var
  Name, Value: UnicodeString;
begin
  Result := '';
  if (Index < 0) or (Index >= FTargetOrder.Count) then Exit;
  Name := FTargetOrder[Index];
  Result := IntToStr(Index + 1) + '. ' + Name;
  Value := MapValue(FRenames, Name);
  if Value <> '' then Result := Result + ' -> ' + Value;
  if FAddedHeaders.IndexOf(Name) >= 0 then Result := Result + ' (+)';
  if MapValue(FConstants, Name) <> '' then Result := Result + ' [const]';
  if MapValue(FFills, Name) <> '' then Result := Result + ' [fill]';
  if MapValue(FEnumerations, Name) <> '' then Result := Result + ' [enum]';
end;

function TTransformConfig.TransformedColumnCount: Integer;
begin
  Result := FTargetOrder.Count;
end;

function TTransformConfig.TransformedHeader(Col: Integer): UnicodeString;
var
  Name, Rename: UnicodeString;
begin
  Result := '';
  if (Col < 0) or (Col >= FTargetOrder.Count) then Exit;
  Name := FTargetOrder[Col];
  Rename := MapValue(FRenames, Name);
  if Rename <> '' then Result := Rename else Result := Name;
end;

function TTransformConfig.TransformedCellValue(Col, SourceRow, DataStart: Integer;
  Document: TCsvDocument): UnicodeString;
var
  Name: UnicodeString;
  SourceCol, P, StartValue, StopValue: Integer;
  EnumText: UnicodeString;
begin
  Result := '';
  if not Assigned(Document) or (Col < 0) or (Col >= FTargetOrder.Count) then Exit;
  if SourceRow < 0 then Exit;
  Name := FTargetOrder[Col];
  SourceCol := HeaderIndex(Name);
  if (SourceCol >= 0) and (SourceRow < Document.RowCount) and
    (SourceCol < Length(Document.Rows[SourceRow].Cells)) then
    Result := Document.CellValue(SourceRow, SourceCol);
  if (Result = '') and (MapValue(FFills, Name) <> '') then
    Result := MapValue(FFills, Name);
  if MapValue(FConstants, Name) <> '' then
    Result := MapValue(FConstants, Name);
  EnumText := MapValue(FEnumerations, Name);
  if EnumText <> '' then
  begin
    P := Pos(':', EnumText);
    StartValue := StrToIntDef(Copy(EnumText, 1, P - 1), 1);
    StopValue := StrToIntDef(Copy(EnumText, P + 1, MaxInt), StartValue);
    if StartValue + SourceRow - DataStart <= StopValue then
      Result := IntToStr(StartValue + SourceRow - DataStart)
    else
      Result := '';
  end;
  if IsDecimalText(Result) and (FNumberFormat = '.') and (Pos(',', Result) > 0) then
    Result := StringReplace(Result, ',', '.', [])
  else if IsDecimalText(Result) and (FNumberFormat = ',') and (Pos('.', Result) > 0) then
    Result := StringReplace(Result, '.', ',', []);
end;

end.
