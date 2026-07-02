unit listplug;

{$mode delphi}{$H+}

interface

uses Windows;

const
  lcs_findfirst = 1;
  lcs_matchcase = 2;
  lcs_wholewords = 4;
  lcs_backwards = 8;

type
  TListDefaultParamStruct = record
    size: LongInt;
    PluginInterfaceVersionLow: LongInt;
    PluginInterfaceVersionHi: LongInt;
    DefaultIniName: array[0..MAX_PATH - 1] of AnsiChar;
  end;
  PListDefaultParamStruct = ^TListDefaultParamStruct;

implementation

end.
