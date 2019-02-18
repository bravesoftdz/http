unit Lib.HTTPClient;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.SyncObjs,
  System.NetEncoding,
  System.Generics.Collections,
  Winapi.Winsock2,
  Lib.TCPSocket,
  Lib.HTTPConsts,
  Lib.HTTPUtils,
  Lib.HTTPSocket;

type
  THTTPClient = class(THTTPSocket)
  private
    FBuffer: TRingBuffer<string>;
    FHost: string;
    FHostName: string;
    FPort: Integer;
    FActive: Boolean;
    FOnResource: TNotifyEvent;
    FOnRequest: TNotifyEvent;
    FOnResponseHeader: TNotifyEvent;
    FOnResponse: TNotifyEvent;
    FOnResponseComplete: TNotifyEvent;
    FOnIdle: TNotifyEvent;
    FOnMessage: TNotifyEvent;
    FMessage: string;
    FKeepAlive: Boolean;
    FKeepAliveTimeout: Cardinal;
    FResponseTimeout: Cardinal;
    procedure UpdateKeepAliveTimeout;
    procedure SetKeepAliveTimeout(Value: Cardinal);
    procedure SetKeepAlive(Value: Boolean);
    procedure DoOnResponseComplete(Sender: TObject);
 protected
    procedure DoExcept(Code: Integer); override;
    procedure DoTimeout(Code: Integer); override;
    procedure DoOpen; override;
    procedure DoClose; override;
    procedure DoRead; override;
    procedure DoReadHeader; override;
    procedure DoReadComplete; override;
    procedure DoMessage(const TextMessage: string);
    procedure DoConnectionClose;
    procedure DoResponseComplete;
    procedure DoRequest;
    procedure GetNext;
  public
    procedure Get(const URL: string);
    procedure SendRequest;
    procedure ShowState;
    constructor Create; override;
    destructor Destroy; override;
    property OnRequest: TNotifyEvent read FOnRequest write FOnRequest;
    property OnResource: TNotifyEvent read FOnResource write FOnResource;
    property OnResponseHeader: TNotifyEvent read FOnResponseHeader write FOnResponseHeader;
    property OnResponse: TNotifyEvent read FOnResponse write FOnResponse;
    property OnResponseComplete: TNotifyEvent read FOnResponseComplete write FOnResponseComplete;
    property OnMessage: TNotifyEvent read FOnMessage write FOnMessage;
    property OnIdle: TNotifyEvent read FOnIdle write FOnIdle;
    property OnDestroy;
    property KeepAlive: Boolean read FKeepAlive write SetKeepAlive;
    property KeepAliveTimeout: Cardinal read FKeepAliveTimeout write SetKeepAliveTimeout;
    property ResponseTimeout: Cardinal read FResponseTimeout write FResponseTimeout;
    property Message: string read FMessage;
  end;

implementation

const
  TIMEOUT_KEEPALIVE=1;
  TIMEOUT_READ=2;

constructor THTTPClient.Create;
begin
  inherited;
  FActive:=False;
  FResponseTimeout:=10000;
  FBuffer.Init;
  OnResponseComplete:=DoOnResponseComplete; //���������� ��-��������� ��� ���������� �������� ������� (������� � �������� ���������� �������)
end;

destructor THTTPClient.Destroy;
begin
  DoMessage('client_destroy');
  inherited;
end;

procedure THTTPClient.UpdateKeepAliveTimeout;
begin
  if KeepAlive then
    SetTimeout(KeepAliveTimeout*1000,TIMEOUT_KEEPALIVE)
  else
    SetTimeout(0,TIMEOUT_KEEPALIVE);
end;

procedure THTTPClient.SetKeepAliveTimeout(Value: Cardinal);
begin
  if FKeepAliveTimeout<>Value then
  begin
    FKeepAliveTimeout:=Value;
    UpdateKeepAliveTimeout;
  end;
end;

procedure THTTPClient.SetKeepAlive(Value: Boolean);
begin
  if FKeepAlive<>Value then
  begin
    FKeepAlive:=Value;
    UpdateKeepAliveTimeout;
  end;
end;

procedure THTTPClient.DoConnectionClose;
begin
  FActive:=False;
  FHost:='';
  Close;
  inherited DoClose;
end;

procedure THTTPClient.DoResponseComplete;
begin
  SetTimeout(0,TIMEOUT_READ);
  UpdateKeepAliveTimeout;
  if Assigned(OnResponseComplete) then FOnResponseComplete(Self);
end;

procedure THTTPClient.DoExcept(Code: Integer);
begin
  FActive:=False;
  FHost:='';
  inherited DoExcept(Code);
end;

procedure THTTPClient.DoTimeout(Code: Integer);
begin
  case Code of
  TIMEOUT_KEEPALIVE: DoMessage('client_keepalive_timeout '+FSocket.ToString);
  TIMEOUT_READ: DoMessage('client_read_timeout '+FSocket.ToString);
  else DoMessage('client_timeout '+FSocket.ToString);
  end;
  DoConnectionClose;
  DoResponseComplete;
end;

procedure THTTPClient.DoOpen;
begin
  DoMessage('client_open '+FSocket.ToString);
  inherited;
end;

procedure THTTPClient.DoClose;
begin
  DoMessage('client_close '+FSocket.ToString);
  DoConnectionClose;
  DoResponseComplete;
end;

procedure THTTPClient.DoOnResponseComplete(Sender: TObject);
begin
  GetNext;
  if not FActive then
  if Assigned(FOnIdle) then FOnIdle(Self);
end;

procedure THTTPClient.DoRead;
begin
  SetTimeout(0,TIMEOUT_KEEPALIVE);
  while Response.DoRead(Read(20000))>0 do;
end;

procedure THTTPClient.DoReadHeader;
begin
  if Assigned(FOnResponseHeader) then FOnResponseHeader(Self);
end;

procedure THTTPClient.DoReadComplete;
begin
  if Assigned(FOnResponse) then FOnResponse(Self);
  FActive:=False;
  if not KeepAlive or (Response.GetHeaderValue('Connection')='close') then
    DoConnectionClose;
  DoResponseComplete;
end;

procedure THTTPClient.DoMessage(const TextMessage: string);
begin
  FMessage:=TextMessage;
  if Assigned(FOnMessage) then FOnMessage(Self);
end;

procedure THTTPClient.DoRequest;
begin
  WriteString(Request.SendHeaders);
  Write(Request.Content);
  if Assigned(FOnRequest) then FOnRequest(Self);
  SetTimeout(ResponseTimeout,TIMEOUT_READ);
end;

procedure THTTPClient.GetNext;
begin

  while not FActive and not FBuffer.EOF do
  begin

    Request.Reset;
    Request.Protocol:='HTTP/1.1';
    Request.Method:='GET';
    Request.ParseURL(FBuffer.Read);
    Request.AddHeaderValue('Host',Request.Host);
    Request.AddHeaderKeepAlive(KeepAlive,KeepAliveTimeout);

    SendRequest;

  end;

end;

procedure THTTPClient.SendRequest;
var
  Port: Integer;
  HostName,HostPort: string;
  ProtocolUseSSL: Boolean;
begin

  if FActive then
  raise Exception.Create('HTTPClient is active');

  HTTPSplitHost(Request.Host,HostName,HostPort);

  ProtocolUseSSL:=SameText(Request.Transport,'https');

  if ProtocolUseSSL then
    Port:=StrToIntDef(HostPort,HTTPS_PORT)
  else
    Port:=StrToIntDef(HostPort,HTTP_PORT);

  Response.ResourceName:=HTTPDecodeResourceName(HTTPExtractResourceName(Request.Resource));
  Response.LocalResource:=HTTPResourceToLocal(Request.Resource);

  if Assigned(FOnResource) then FOnResource(Self);

  if (FHost='') or (FHostName<>HostName) or (FPort<>Port) then
  begin
    if FSocket>0 then DoConnectionClose;
    UseSSL:=ProtocolUseSSL;
    if not ConnectTo(HostName,Port) then Exit;
  end;

  FActive:=True;

  FHost:=Request.Host;
  FHostName:=HostName;
  FPort:=Port;

  DoRequest;

end;

procedure THTTPClient.Get(const URL: string);
begin
  FBuffer.Write(URL);
  GetNext;
end;

procedure THTTPClient.ShowState;
var S: string;
begin
  if FActive then S:='active' else S:='inactive';
  DoMessage(FSocket.ToString+' '+S+' '+FHostName+' '+Request.Resource+' '+
    Response.ContentReaded.ToString+'/'+Response.ContentLength.ToString);
end;

end.
