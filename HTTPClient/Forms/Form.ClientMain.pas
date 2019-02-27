unit Form.ClientMain;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Variants,
  System.Classes,
  System.IOUtils,
  System.JSON,
  Vcl.Graphics,
  Vcl.Imaging.JPEG,
  Vcl.Imaging.GIFImg,
  Vcl.Imaging.pngimage,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.ComCtrls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Samples.Gauges,
  Vcl.Buttons,
  Lib.JSON.Store,
  Lib.HTTPConsts,
  Lib.HTTPClient,
  Lib.HTTPContent,
  Form.Request, Frame.Communication;

type
  TForm2 = class(TForm)
    ListBox1: TListBox;
    Edit1: TEdit;
    Button1: TButton;
    Button2: TButton;
    StatusBar1: TStatusBar;
    Button3: TButton;
    CheckBox1: TCheckBox;
    Edit2: TEdit;
    Label1: TLabel;
    Edit3: TEdit;
    Button5: TButton;
    Button6: TButton;
    CommunicationFrame: TCommunicationFrame;
    procedure Button2Click(Sender: TObject);
    procedure ListBox1MouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure Button1Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure Button5Click(Sender: TObject);
    procedure Button6Click(Sender: TObject);
  private
    FHTTPClient: THTTPClient;
    FStore: TJSONStore;
    procedure CreateClient;
    procedure OnClientClose(Sender: TObject);
    procedure OnClientRequest(Sender: TObject);
    procedure OnClientResponse(Sender: TObject);
    procedure OnClientMessage(Sender: TObject);
    procedure OnClientResource(Sender: TObject);
    procedure OnIdle(Sender: TObject);
    procedure OnClientException(Sender: TObject);
  public
  end;

var
  Form2: TForm2;

implementation

{$R *.dfm}

procedure TForm2.FormCreate(Sender: TObject);
begin

  FStore:=TJSONStore.Create(ExtractFilePath(ParamStr(0))+'client-store.json');

  BoundsRect:=FStore.ReadRect('form.bounds',BoundsRect);
  Edit1.Text:=FStore.ReadString('url-edit');
  Edit3.Text:=FStore.ReadString('local-storage','');
  Edit2.Text:=FStore.ReadInteger('keep-alive.timeout',10).ToString;
  CheckBox1.Checked:=FStore.ReadBool('keep-alive.enabled',False);
  FStore.ReadStrings('urls',ListBox1.Items);

  CommunicationFrame.Reset;

end;

procedure TForm2.FormDestroy(Sender: TObject);
begin

  if WindowState=TWindowState.wsNormal then
  FStore.WriteRect('form.bounds',BoundsRect);
  FStore.WriteString('url-edit',Edit1.Text);
  FStore.WriteString('local-storage',Edit3.Text);
  FStore.WriteInteger('keep-alive.timeout',StrToIntDef(Edit2.Text,10));
  FStore.WriteBool('keep-alive.enabled',CheckBox1.Checked);
  FStore.WriteStrings('urls',ListBox1.Items);

  FStore.Free;

end;

procedure TForm2.Button1Click(Sender: TObject);
begin
  CommunicationFrame.Reset;
  CreateClient;
  FHTTPClient.Get(Edit1.Text);
end;

procedure TForm2.Button2Click(Sender: TObject);
begin
  if (Edit1.Text<>'') and (ListBox1.Items.IndexOf(Edit1.Text)=-1) then
  begin
    ListBox1.Items.Add(Edit1.Text);
    ListBox1.ItemIndex:=ListBox1.Items.Count-1;
  end;
end;

procedure TForm2.Button3Click(Sender: TObject);
var S: string;
begin
  CommunicationFrame.Reset;
  CreateClient;
  for S in ListBox1.Items do FHTTPClient.Get(S);
end;

procedure TForm2.Button5Click(Sender: TObject);
begin
  ListBox1.Items.Delete(ListBox1.ItemIndex);
end;

procedure TForm2.Button6Click(Sender: TObject);
var F: TRequestForm;
begin

  F:=TRequestForm.Create(Self);
  F.SetURL(Edit1.Text);
  F.Request.AddHeaderKeepAlive(CheckBox1.Checked,StrToInt64Def(Edit2.Text,0));

  if F.Execute then
  begin
    CommunicationFrame.Reset;
    CreateClient;
    FHTTPClient.Request.Assign(F.Request);
    FHTTPClient.SendRequest;
  end;

end;

procedure TForm2.ListBox1MouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var I: Integer;
begin
  I:=ListBox1.ItemAtPos(Point(X,Y),True);
  if I<>-1 then Edit1.Text:=ListBox1.Items[I];
end;

procedure TForm2.CreateClient;
begin

  if not Assigned(FHTTPClient) then
  begin

    FHTTPClient:=THTTPClient.Create;
    FHTTPClient.OnRequest:=OnClientRequest;
    FHTTPClient.OnResponse:=OnClientResponse;
    FHTTPClient.OnMessage:=OnClientMessage;
    FHTTPClient.OnResource:=OnClientResource;
    FHTTPClient.OnClose:=OnClientClose;
    FHTTPClient.OnIdle:=OnIdle;
    FHTTPClient.OnException:=OnClientException;

  end;

  FHTTPClient.KeepAliveTimeout:=StrToInt64Def(Edit2.Text,0);
  FHTTPClient.KeepAlive:=CheckBox1.Checked;

end;

procedure TForm2.OnClientRequest(Sender: TObject);
begin
  CommunicationFrame.SetRequest(THTTPClient(Sender).Request);
end;

procedure TForm2.OnClientResponse(Sender: TObject);
var C: THTTPClient; ContentFileName: string;
begin

  C:=THTTPClient(Sender);

  CommunicationFrame.SetResponse(C.Response);

  ContentFileName:=Edit3.Text+ExtractFileName(C.Response.LocalResource);

  if Length(C.Response.Content)>0 then
    TFile.WriteAllBytes(ContentFileName,C.Response.Content);

  if C.Response.ResultCode=HTTPCODE_MOVED_PERMANENTLY then
  begin
    C.Request.ParseURL(C.Response.GetHeaderValue('Location'));
    C.Request.AddHeaderValue('Host',C.Request.Host);
    C.SendRequest;
  end;

end;

procedure TForm2.OnClientMessage(Sender: TObject);
var C: THTTPClient;
begin
  C:=THTTPClient(Sender);
  CommunicationFrame.ToLog(C.Message+CRLF);
end;

procedure TForm2.OnClientResource(Sender: TObject);
begin
  StatusBar1.SimpleText:=THTTPClient(Sender).Request.Resource;
end;

procedure TForm2.OnIdle(Sender: TObject);
begin
  StatusBar1.SimpleText:='Complete';
end;

procedure TForm2.OnClientClose(Sender: TObject);
begin
end;

procedure TForm2.OnClientException(Sender: TObject);
var C: THTTPClient;
begin
  C:=THTTPClient(Sender);
  CommunicationFrame.ToLog(C.ExceptionCode.ToString+' '+C.ExceptionMessage+CRLF);
end;

end.
