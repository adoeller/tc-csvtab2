unit uColumnSample;

{$mode delphi}{$H+}

interface

function SampleCount(VisibleCount, MaxSamples: Integer): Integer;
function SamplePosition(SampleNo, Samples, VisibleCount: Integer): Integer;

implementation

function SampleCount(VisibleCount, MaxSamples: Integer): Integer;
begin
  if (VisibleCount <= 0) or (MaxSamples <= 0) then Exit(0);
  if VisibleCount < MaxSamples then Result := VisibleCount
  else Result := MaxSamples;
end;

function SamplePosition(SampleNo, Samples, VisibleCount: Integer): Integer;
begin
  if (VisibleCount <= 1) or (Samples <= 1) then Exit(0);
  Result := Int64(SampleNo) * (Int64(VisibleCount) - 1) div
    (Int64(Samples) - 1);
end;

end.
