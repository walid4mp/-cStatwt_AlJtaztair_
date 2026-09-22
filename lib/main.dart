import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

const green = Color(0xFF087F3E);
const deepGreen = Color(0xFF064E2A);
const red = Color(0xFFD71920);
const ink = Color(0xFF10251A);

const wilayas = [
  'أدرار','الشلف','الأغواط','أم البواقي','باتنة','بجاية','بسكرة','بشار','البليدة','البويرة',
  'تمنراست','تبسة','تلمسان','تيارت','تيزي وزو','الجزائر','الجلفة','جيجل','سطيف','سعيدة',
  'سكيكدة','سيدي بلعباس','عنابة','قالمة','قسنطينة','المدية','مستغانم','المسيلة','معسكر','ورقلة',
  'وهران','البيض','إليزي','برج بوعريريج','بومرداس','الطارف','تندوف','تيسمسيلت','الوادي','خنشلة',
  'سوق أهراس','تيبازة','ميلة','عين الدفلى','النعامة','عين تموشنت','غليزان','تيميمون','برج باجي مختار',
  'أولاد جلال','بني عباس','عين صالح','عين قزام','تقرت','جانت','المغير','المنيعة'
];

const reportTypes = ['مدني','مفقودات','خدمات','سلامة عامة','احتيال/نصب'];

class Api {
  static const _configuredBase = String.fromEnvironment('API_URL');
  static const productionBase = 'https://cstatwt-aljtaztair.onrender.com';
  static String get base {
    final value = _configuredBase.trim();
    if (value.isEmpty) return productionBase;
    return value.replaceFirst(RegExp(r'/+$'), '');
  }
  String? token;
  String? get userId => token == null ? null : _decodeJwtSubject(token!);

  static String? _decodeJwtSubject(String value) {
    try {
      final parts = value.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      return payload is Map ? payload['id']?.toString() : null;
    } catch (_) {
      return null;
    }
  }
  Future<void> load() async => token = (await SharedPreferences.getInstance()).getString('token');
  Map<String,String> headers({bool jsonBody=false}) => {
    if (jsonBody) 'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token'
  };
  Future<http.Response> get(String path) => http.get(Uri.parse('$base$path'), headers: headers());
  Future<http.Response> postJson(String path, Map<String,dynamic> body) =>
      http.post(Uri.parse('$base$path'), headers: headers(jsonBody:true), body: jsonEncode(body));
  Future<http.Response> patchJson(String path, Map<String,dynamic> body) =>
      http.patch(Uri.parse('$base$path'), headers: headers(jsonBody:true), body: jsonEncode(body));
  Future<void> saveToken(String t) async {
    token=t;
    (await SharedPreferences.getInstance()).setString('token', t);
  }
  Future<void> clear() async { token=null; (await SharedPreferences.getInstance()).remove('token'); }
  Future<Map<String,dynamic>> json(http.Response r) async {
    final d=jsonDecode(r.body);
    if(r.statusCode>=400) throw Exception(d['error'] ?? 'حدث خطأ');
    return Map<String,dynamic>.from(d);
  }
}

final api=Api();

class User {
  final String id, username, name;
  final String? avatarUrl, wilaya, bio, phone, whatsapp, role;
  final bool verified;
  User({required this.id,required this.username,required this.name,this.avatarUrl,this.wilaya,this.bio,this.phone,this.whatsapp,this.role,required this.verified});
  factory User.fromJson(Map<String,dynamic> j)=>User(
    id:j['id'],username:j['username'],name:j['name'],avatarUrl:j['avatarUrl'],wilaya:j['wilaya'],
    bio:j['bio'],phone:j['phone'],whatsapp:j['whatsapp'],role:j['role'],verified:j['isVerified']==true);
}

class Post {
  final Map<String,dynamic> raw;
  Post(this.raw);
  String get id=>raw['id'];
  String get body=>raw['body']??'';
  String get title=>raw['title']??'';
  String? get media=>raw['mediaUrl'];
  String? get mediaType=>raw['mediaType'];
  double? get lat=>(raw['latitude'] as num?)?.toDouble();
  double? get lon=>(raw['longitude'] as num?)?.toDouble();
  User get author=>User.fromJson(raw['author']);
}

class Report {
  final Map<String,dynamic> raw;
  Report(this.raw);
  String get id=>raw['id'];
  String get title=>raw['title']??'';
  String get description=>raw['description']??'';
  String get type=>raw['type']??'';
  String get wilaya=>raw['wilaya']??'';
  String get status=>raw['status']??'PENDING';
  double? get lat=>(raw['latitude'] as num?)?.toDouble();
  double? get lon=>(raw['longitude'] as num?)?.toDouble();
  String? get media=>raw['mediaUrl'];
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await api.load();
  runApp(const SawtApp());
}

class SawtApp extends StatelessWidget {
  const SawtApp({super.key});
  @override
  Widget build(BuildContext context)=>MaterialApp(
    debugShowCheckedModeBanner:false,
    title:'صوت الجزائر',
    theme:ThemeData(
      useMaterial3:true, colorScheme:ColorScheme.fromSeed(seedColor:green),
      scaffoldBackgroundColor:const Color(0xFFF4F8F5),
      fontFamily:'Arial',
      appBarTheme:const AppBarTheme(backgroundColor:Colors.transparent, elevation:0, foregroundColor:ink),
      inputDecorationTheme:InputDecorationTheme(
        filled:true, fillColor:Colors.white, border:OutlineInputBorder(borderRadius:BorderRadius.circular(18),borderSide:BorderSide.none),
        contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:15)),
      cardTheme:CardThemeData(elevation:0, color:Colors.white, shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22))),
    ),
    home: api.token==null ? const Welcome() : const Shell(),
  );
}

class Welcome extends StatelessWidget {
  const Welcome({super.key});
  @override
  Widget build(BuildContext context)=>Scaffold(
    body:Stack(children:[
      Positioned.fill(child:Image.asset('assets/branding/app_poster.png',fit:BoxFit.cover)),
      Positioned.fill(child:Container(color:Colors.black.withValues(alpha:.55))),
      SafeArea(child:Padding(
        padding:const EdgeInsets.all(24),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          const Spacer(),
          const Icon(Icons.shield_rounded,size:80,color:Colors.white),
          const SizedBox(height:12),
          const Text('صوت الجزائر',textAlign:TextAlign.center,style:TextStyle(fontSize:38,fontWeight:FontWeight.w900,color:Colors.white)),
          const Text('أبلغ • شارك • احمِ مجتمعك',textAlign:TextAlign.center,style:TextStyle(fontSize:18,color:Colors.white70)),
          const SizedBox(height:30),
          FilledButton(
            style:FilledButton.styleFrom(backgroundColor:green,padding:const EdgeInsets.symmetric(vertical:16)),
            onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AuthPage(register:true))), child:const Text('إنشاء حساب جديد')),
          const SizedBox(height:10),
          OutlinedButton(
            style:OutlinedButton.styleFrom(foregroundColor:Colors.white,side:const BorderSide(color:Colors.white),padding:const EdgeInsets.symmetric(vertical:16)),
            onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AuthPage(register:false))), child:const Text('تسجيل الدخول')),
          const SizedBox(height:20),
          const Text('منصة مجتمعية للإبلاغ والمتابعة والمشاركة. البلاغات تخضع للمراجعة ولا تُعد أحكامًا نهائية.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white70,fontSize:12)),
        ]))),
    ]));
}

class AuthPage extends StatefulWidget {
  final bool register;
  const AuthPage({super.key,required this.register});
  @override State<AuthPage> createState()=>_AuthPageState();
}
class _AuthPageState extends State<AuthPage>{
  final email=TextEditingController(), password=TextEditingController(), username=TextEditingController(), name=TextEditingController();
  String? wilaya; bool busy=false;
  Future<void> submit() async {
    setState(()=>busy=true);
    try{
      final path=widget.register?'/auth/register':'/auth/login';
      final body=<String,dynamic>{'email':email.text.trim(),'password':password.text};
      if(widget.register){body.addAll({'username':username.text.trim(),'name':name.text.trim(),'wilaya':wilaya});}
      final r=await api.postJson(path,body); final d=await api.json(r); await api.saveToken(d['token']);
      if(mounted) Navigator.pushAndRemoveUntil(context,MaterialPageRoute(builder:(_)=>const Shell()),(_)=>false);
    }catch(e){if(mounted){var msg=e.toString().replaceFirst('Exception: ','');if(msg.contains('Internal server error'))msg='تعذر إنشاء الحساب. تحقق من اتصال الخادم وقاعدة البيانات.';ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(msg)));}}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.register?'إنشاء حساب':'تسجيل الدخول')),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      Container(height:130,decoration:BoxDecoration(borderRadius:BorderRadius.circular(28),image:const DecorationImage(image:AssetImage('assets/branding/app_poster.png'),fit:BoxFit.cover))),
      const SizedBox(height:20),
      if(widget.register) ...[
        TextField(controller:name,decoration:const InputDecoration(labelText:'الاسم')),
        const SizedBox(height:10),
        TextField(controller:username,decoration:const InputDecoration(labelText:'اسم المستخدم')),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(initialValue:wilaya,items:wilayas.map((w)=>DropdownMenuItem(value:w,child:Text(w))).toList(),onChanged:(v)=>setState(()=>wilaya=v),decoration:const InputDecoration(labelText:'الولاية')),
        const SizedBox(height:10),
      ],
      TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'البريد الإلكتروني')),
      const SizedBox(height:10),
      TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'كلمة المرور')),
      const SizedBox(height:22),
      FilledButton(onPressed:busy?null:submit,style:FilledButton.styleFrom(backgroundColor:green,padding:const EdgeInsets.symmetric(vertical:16)),child:Text(busy?'جاري المعالجة...':widget.register?'إنشاء الحساب':'دخول')),
    ]));
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override State<Shell> createState()=>_ShellState();
}
class _ShellState extends State<Shell>{
  int index=0;
  final pages=const [HomePage(),ReportsPage(),MapPage(),MessagesPage(),ProfilePage()];
  @override Widget build(BuildContext context)=>Scaffold(
    body:pages[index],
    floatingActionButton:(index==0||index==1)?FloatingActionButton.extended(heroTag:'report',backgroundColor:green,foregroundColor:Colors.white,
      onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const CreateReportPage())),
      icon:const Icon(Icons.add_alert_rounded),label:const Text('إنشاء بلاغ')):null,
    bottomNavigationBar:NavigationBar(
      selectedIndex:index,onDestinationSelected:(i)=>setState(()=>index=i),
      destinations:const[
        NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'الرئيسية'),
        NavigationDestination(icon:Icon(Icons.fact_check_outlined),selectedIcon:Icon(Icons.fact_check),label:'البلاغات'),
        NavigationDestination(icon:Icon(Icons.map_outlined),selectedIcon:Icon(Icons.map),label:'الخريطة'),
        NavigationDestination(icon:Icon(Icons.chat_bubble_outline),selectedIcon:Icon(Icons.chat_bubble),label:'المحادثات'),
        NavigationDestination(icon:Icon(Icons.person_outline),selectedIcon:Icon(Icons.person),label:'حسابي'),
      ]));
}

class AppMark extends StatelessWidget {
  final double size;
  const AppMark({super.key,this.size=48});
  @override Widget build(BuildContext context)=>Container(
    width:size,height:size,
    decoration:BoxDecoration(borderRadius:BorderRadius.circular(size*0.30),boxShadow:[BoxShadow(color:deepGreen.withValues(alpha: .18),blurRadius:10,offset:const Offset(0,4))],gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[deepGreen,green])),
    child:Stack(alignment:Alignment.center,children:[
      ClipRRect(borderRadius:BorderRadius.circular(size*.22),child:Row(children:[Expanded(child:Container(color:Colors.white)),Expanded(child:Container(color:red))])),
      Container(width:size*.66,height:size*.66,decoration:BoxDecoration(color:deepGreen.withValues(alpha: .92),shape:BoxShape.circle,border:Border.all(color:Colors.white,width:2)),child:Icon(Icons.shield_rounded,color:Colors.white,size:size*.40)),
      Positioned(bottom:size*.10,child:Icon(Icons.location_on_rounded,color:red,size:size*.22)),
    ]));
}

class TopHeader extends StatelessWidget {
  final String title; final String? subtitle;
  const TopHeader({super.key,required this.title,this.subtitle});
  @override Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.fromLTRB(18,18,18,8),
    child:Row(children:[
      const AppMark(),
      const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900,color:ink)),
        if(subtitle!=null) Text(subtitle!,style:const TextStyle(color:Colors.black54)),
      ])),
      IconButton(onPressed:()=>showSearch(context:context,delegate:UserSearchDelegate()),icon:const Icon(Icons.search)),
    ]));
}

class HomePage extends StatefulWidget {const HomePage({super.key}); @override State<HomePage> createState()=>_HomePageState();}
class _HomePageState extends State<HomePage>{
  List<Report> reports=[]; bool loading=true;
  Future<void> load() async {
    setState(()=>loading=true);
    try {
      final r=await api.get('/reports');
      final data=jsonDecode(r.body) as List;
      reports=data.map((e)=>Report(Map<String,dynamic>.from(e))).toList();
    } catch (_) {}
    finally { if(mounted)setState(()=>loading=false); }
  }
  @override void initState(){super.initState();load();}
  @override Widget build(BuildContext context)=>RefreshIndicator(
    onRefresh:load, child:CustomScrollView(slivers:[
      SliverToBoxAdapter(child:TopHeader(title:'صوت الجزائر',subtitle:'أبلغ • شارك • احمِ وطنك')),
      SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(16,6,16,10),child:Row(children:[
        Expanded(child:_QuickAction(icon:Icons.add_alert_rounded,title:'إنشاء بلاغ',onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const CreateReportPage())))),
        const SizedBox(width:10),
        Expanded(child:_QuickAction(icon:Icons.map_outlined,title:'خريطة البلاغات',onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const MapPage())))),
      ]))),
      if(loading) const SliverFillRemaining(child:Center(child:CircularProgressIndicator()))
      else if(reports.isEmpty) const SliverFillRemaining(child:Center(child:Text('لا توجد بلاغات منشورة بعد')))
      else SliverList.builder(itemCount:reports.length,itemBuilder:(_,i)=>ReportHomeCard(report:reports[i])),
    ]));
}

class ReportHomeCard extends StatelessWidget {
  final Report report;
  const ReportHomeCard({super.key,required this.report});
  @override Widget build(BuildContext context)=>Card(margin:const EdgeInsets.fromLTRB(16,6,16,8),child:InkWell(
    borderRadius:BorderRadius.circular(18),
    onTap:()=>showModalBottomSheet(context:context,isScrollControlled:true,builder:(_)=>ReportDetails(report:report)),
    child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const Icon(Icons.flag_rounded,color:green),const SizedBox(width:8),Expanded(child:Text(report.title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))),
        Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),decoration:BoxDecoration(color:report.status=='RESOLVED'?green.withValues(alpha:.12):Colors.orange.withValues(alpha:.12),borderRadius:BorderRadius.circular(20)),child:Text(report.status,style:const TextStyle(fontSize:11,fontWeight:FontWeight.bold)))
      ]),
      const SizedBox(height:7),Text(report.description,maxLines:3,overflow:TextOverflow.ellipsis),
      const SizedBox(height:8),Row(children:[Icon(Icons.location_on_outlined,size:18,color:green),const SizedBox(width:4),Text('${report.wilaya}${report.type.isNotEmpty?' • ${report.type}':''}'),const Spacer(),const Icon(Icons.chevron_left)]),
      if(report.media!=null)Padding(padding:const EdgeInsets.only(top:10),child:ClipRRect(borderRadius:BorderRadius.circular(14),child:Image.network(report.media!,height:180,width:double.infinity,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const SizedBox.shrink())))
    ]))));
}

class _QuickAction extends StatelessWidget {
  final IconData icon; final String title; final VoidCallback onTap;
  const _QuickAction({required this.icon,required this.title,required this.onTap});
  @override Widget build(BuildContext context)=>Material(color:Colors.white,borderRadius:BorderRadius.circular(18),child:InkWell(onTap:onTap,borderRadius:BorderRadius.circular(18),child:Padding(padding:const EdgeInsets.symmetric(vertical:14,horizontal:7),child:Column(children:[Icon(icon,color:green,size:27),const SizedBox(height:6),Text(title,textAlign:TextAlign.center,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w800))]))));
}

class PostCard extends StatefulWidget {
  final Post post; final Future<void> Function() onRefresh;
  const PostCard({super.key,required this.post,required this.onRefresh});
  @override State<PostCard> createState()=>_PostCardState();
}
class _PostCardState extends State<PostCard>{
  bool liked=false,saved=false; final comment=TextEditingController();
  Future<void> action(String p) async {try{final r=await api.postJson(p,{});final d=await api.json(r);setState(()=>p.contains('/like')?liked=d['liked']==true:saved=d['saved']==true);}catch(_){}} 
  @override Widget build(BuildContext context)=>Card(
    margin:const EdgeInsets.fromLTRB(14,8,14,10),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[CircleAvatar(backgroundColor:green,backgroundImage:widget.post.author.avatarUrl!=null?NetworkImage(widget.post.author.avatarUrl!):null,child:widget.post.author.avatarUrl==null?Text(widget.post.author.name.isNotEmpty?widget.post.author.name.substring(0,1):'?'):null),
        const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Text(widget.post.author.name,style:const TextStyle(fontWeight:FontWeight.bold)),if(widget.post.author.verified)const Padding(padding:EdgeInsets.only(right:5),child:Icon(Icons.verified,size:17,color:green))]),
          Text('@${widget.post.author.username}',style:const TextStyle(color:Colors.black45,fontSize:12))
        ])),IconButton(onPressed:(){},icon:const Icon(Icons.more_horiz))]),
      if(widget.post.title.isNotEmpty)Padding(padding:const EdgeInsets.only(top:10),child:Text(widget.post.title,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:18))),
      Padding(padding:const EdgeInsets.only(top:6),child:Text(widget.post.body)),
      if(widget.post.media!=null) ...[
        const SizedBox(height:10),
        ClipRRect(borderRadius:BorderRadius.circular(18),child:widget.post.mediaType=='VIDEO'?SizedBox(height:250,child:VideoPreview(url:widget.post.media!)):Image.network(widget.post.media!,height:250,width:double.infinity,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(height:200,color:Colors.black12,child:const Icon(Icons.image_not_supported)))),
      ],
      const SizedBox(height:6),
      Row(children:[
        IconButton(tooltip:'إعجاب',onPressed:()=>action('/posts/${widget.post.id}/like'),icon:Icon(liked?Icons.favorite:Icons.favorite_border,color:liked?red:null)),
        IconButton(tooltip:'تعليقات',onPressed:()=>showComments(context),icon:const Icon(Icons.chat_bubble_outline)),
        IconButton(tooltip:'حفظ',onPressed:()=>action('/posts/${widget.post.id}/save'),icon:Icon(saved?Icons.bookmark:Icons.bookmark_border)),
        if(widget.post.lat!=null&&widget.post.lon!=null)IconButton(tooltip:'عرض الموقع على الخريطة',onPressed:()=>showPostMap(context),icon:const Icon(Icons.location_on_outlined,color:green)),
        const Spacer(),Text(DateFormat('dd/MM HH:mm').format(DateTime.parse(widget.post.raw['createdAt'])))
      ])
    ])));
  void showComments(BuildContext context)=>showModalBottomSheet(context:context,isScrollControlled:true,builder:(_)=>CommentsSheet(postId:widget.post.id));
  void showPostMap(BuildContext context)=>showModalBottomSheet(context:context,isScrollControlled:true,builder:(_)=>SizedBox(height:MediaQuery.of(context).size.height*.72,child:Column(children:[
    const Padding(padding:EdgeInsets.all(14),child:Text('موقع المنشور',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900))),
    Expanded(child:FlutterMap(options:MapOptions(initialCenter:LatLng(widget.post.lat!,widget.post.lon!),initialZoom:15),children:[
      TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'dz.sawt.aljazair'),
      MarkerLayer(markers:[Marker(point:LatLng(widget.post.lat!,widget.post.lon!),width:54,height:54,child:const Icon(Icons.location_pin,color:red,size:50))])
    ]))
  ])));
}

class VideoPreview extends StatefulWidget {final String url;const VideoPreview({super.key,required this.url});@override State<VideoPreview> createState()=>_VideoPreviewState();}
class _VideoPreviewState extends State<VideoPreview>{
  late VideoPlayerController c; Future<void>? f;
  @override void initState(){super.initState();c=VideoPlayerController.networkUrl(Uri.parse(widget.url));f=c.initialize();}
  @override void dispose(){c.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>FutureBuilder(future:f,builder:(_,s)=>s.connectionState==ConnectionState.done?Stack(alignment:Alignment.center,children:[
    AspectRatio(aspectRatio:c.value.aspectRatio,child:VideoPlayer(c)),IconButton(onPressed:(){setState(()=>c.value.isPlaying?c.pause():c.play());},icon:Icon(c.value.isPlaying?Icons.pause_circle:Icons.play_circle,color:Colors.white,size:58))
  ]):const SizedBox(height:250,child:Center(child:CircularProgressIndicator())));
}

class CommentsSheet extends StatefulWidget {final String postId;const CommentsSheet({super.key,required this.postId});@override State<CommentsSheet> createState()=>_CommentsSheetState();}
class _CommentsSheetState extends State<CommentsSheet>{
  List<dynamic> rows=[];final c=TextEditingController();
  Future<void> load()async{final r=await api.get('/posts/${widget.postId}/comments');setState(()=>rows=jsonDecode(r.body));}
  @override void initState(){super.initState();load();}
  @override Widget build(BuildContext context)=>Padding(padding:EdgeInsets.only(bottom:MediaQuery.of(context).viewInsets.bottom),child:SafeArea(child:SizedBox(height:500,child:Column(children:[
    const Padding(padding:EdgeInsets.all(16),child:Text('التعليقات',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold))),
    Expanded(child:ListView.builder(itemCount:rows.length,itemBuilder:(_,i)=>ListTile(title:Text(rows[i]['user']['name']),subtitle:Text(rows[i]['body'])))),
    Row(children:[Expanded(child:TextField(controller:c,decoration:const InputDecoration(hintText:'اكتب تعليقًا...'))),IconButton(onPressed:()async{if(c.text.trim().isEmpty)return;await api.postJson('/posts/${widget.postId}/comments',{'body':c.text.trim()});c.clear();load();},icon:const Icon(Icons.send,color:green))])
  ]))));
}

class CreateReportPage extends StatefulWidget {const CreateReportPage({super.key});@override State<CreateReportPage> createState()=>_CreateReportPageState();}
class _CreateReportPageState extends State<CreateReportPage>{
  final title=TextEditingController(),desc=TextEditingController(),city=TextEditingController();
  String type=reportTypes.first,wilaya=wilayas[30]; bool anonymous=false,busy=false; LatLng? picked; final media=<XFile>[];
  Future<void> pick(bool video)async{final p=ImagePicker();final x=video?await p.pickVideo(source:ImageSource.gallery):await p.pickImage(source:ImageSource.gallery,imageQuality:82);if(x!=null)setState(()=>media.add(x));}
  Future<void> locate()async{
    if(!await Geolocator.isLocationServiceEnabled()){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('فعّل خدمة الموقع أولًا')));return;}
    var p=await Geolocator.checkPermission();if(p==LocationPermission.denied)p=await Geolocator.requestPermission();
    if(p==LocationPermission.denied||p==LocationPermission.deniedForever){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('اسمح للتطبيق باستخدام الموقع')));return;}
    final current=await Geolocator.getCurrentPosition();
    if(mounted)setState(()=>picked=LatLng(current.latitude,current.longitude));
  }
  Future<void> openPicker()async{
    final result=await Navigator.push<LatLng>(context,MaterialPageRoute(builder:(_)=>MapLocationPickerPage(initial:picked)));
    if(result!=null&&mounted)setState(()=>picked=result);
  }
  Future<void> submit()async{
    if(title.text.trim().isEmpty||desc.text.trim().isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أكمل العنوان والوصف')));return;}
    if(picked==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('حدد مكان وقوع البلاغ على الخريطة أولًا')));return;}
    setState(()=>busy=true);
    try{
      final req=http.MultipartRequest('POST',Uri.parse('${Api.base}/reports')); req.headers.addAll(api.headers());
      req.fields.addAll({'type':type,'title':title.text.trim(),'description':desc.text.trim(),'wilaya':wilaya,'city':city.text.trim(),'anonymous':'$anonymous','latitude':'${picked!.latitude}','longitude':'${picked!.longitude}'});
      for(final x in media){req.files.add(await http.MultipartFile.fromPath('media',x.path));}
      final r=await req.send();final body=await r.stream.bytesToString();if(r.statusCode>=400)throw Exception((jsonDecode(body) as Map)['error']??'فشل إرسال البلاغ');
      if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم إرسال البلاغ للمراجعة')));Navigator.pop(context);}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('إنشاء بلاغ')),body:ListView(padding:const EdgeInsets.all(18),children:[
    Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:deepGreen,borderRadius:BorderRadius.circular(24)),child:const Row(children:[Icon(Icons.shield_rounded,color:Colors.white,size:38),SizedBox(width:12),Expanded(child:Text('بلاغك يمر بالمراجعة. لا تنشر بيانات شخصية أو اتهامات كحقائق.',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w700)))])),
    const SizedBox(height:14),DropdownButtonFormField(initialValue:type,items:reportTypes.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>type=v!),decoration:const InputDecoration(labelText:'نوع البلاغ')),
    const SizedBox(height:10),TextField(controller:title,decoration:const InputDecoration(labelText:'العنوان')),
    const SizedBox(height:10),TextField(controller:desc,maxLines:5,decoration:const InputDecoration(labelText:'الوصف')),
    const SizedBox(height:10),DropdownButtonFormField(initialValue:wilaya,items:wilayas.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>wilaya=v!),decoration:const InputDecoration(labelText:'الولاية')),
    const SizedBox(height:10),TextField(controller:city,decoration:const InputDecoration(labelText:'المدينة/البلدية (اختياري)')),
    const SizedBox(height:14),Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('موقع وقوع البلاغ',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
      const SizedBox(height:5),const Text('اضغط لتفتح الخريطة ثم حرّك المؤشر وحدد المكان بدقة.',style:TextStyle(color:Colors.black54)),
      const SizedBox(height:10),SizedBox(height:180,child:ClipRRect(borderRadius:BorderRadius.circular(18),child:FlutterMap(options:MapOptions(initialCenter:picked??const LatLng(28.0339,1.6596),initialZoom:picked==null?5:15,interactionOptions:const InteractionOptions(flags:InteractiveFlag.none)),children:[TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'dz.sawt.aljazair'),if(picked!=null)MarkerLayer(markers:[Marker(point:picked!,width:54,height:54,child:const Icon(Icons.location_pin,color:red,size:50))])]))),
      const SizedBox(height:10),Row(children:[Expanded(child:FilledButton.icon(onPressed:openPicker,icon:const Icon(Icons.map_rounded),label:Text(picked==null?'تحديد الموقع على الخريطة':'تغيير الموقع'))),const SizedBox(width:8),IconButton.filled(onPressed:locate,tooltip:'استخدام موقعي الحالي',icon:const Icon(Icons.my_location))])
    ]))),
    const SizedBox(height:12),Row(children:[OutlinedButton.icon(onPressed:()=>pick(false),icon:const Icon(Icons.photo),label:const Text('صورة')),const SizedBox(width:8),OutlinedButton.icon(onPressed:()=>pick(true),icon:const Icon(Icons.video_library),label:const Text('فيديو'))]),
    if(media.isNotEmpty)Text('الملفات المختارة: ${media.length}',style:const TextStyle(fontWeight:FontWeight.bold)),
    SwitchListTile(value:anonymous,onChanged:(v)=>setState(()=>anonymous=v),title:const Text('إرسال كمجهول'),subtitle:const Text('يبقى الحساب معروفًا للنظام والمراجعين المصرح لهم')),
    const SizedBox(height:10),FilledButton.icon(onPressed:busy?null:submit,icon:const Icon(Icons.send_rounded),label:Text(busy?'جاري الإرسال...':'إرسال البلاغ'),style:FilledButton.styleFrom(backgroundColor:green,padding:const EdgeInsets.all(16)))
  ]));
}

class MapLocationPickerPage extends StatefulWidget {final LatLng? initial;const MapLocationPickerPage({super.key,this.initial});@override State<MapLocationPickerPage> createState()=>_MapLocationPickerPageState();}
class _MapLocationPickerPageState extends State<MapLocationPickerPage>{
  late LatLng selected;
  @override void initState(){super.initState();selected=widget.initial??const LatLng(28.0339,1.6596);}
  Future<void> current()async{if(!await Geolocator.isLocationServiceEnabled())return;var p=await Geolocator.checkPermission();if(p==LocationPermission.denied)p=await Geolocator.requestPermission();if(p==LocationPermission.denied||p==LocationPermission.deniedForever)return;final x=await Geolocator.getCurrentPosition();if(mounted)setState(()=>selected=LatLng(x.latitude,x.longitude));}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('تحديد موقع البلاغ'),actions:[IconButton(onPressed:current,tooltip:'موقعي الحالي',icon:const Icon(Icons.my_location))]),body:Stack(children:[
    FlutterMap(options:MapOptions(initialCenter:selected,initialZoom:widget.initial==null?5:15,onTap:(_,point)=>setState(()=>selected=point)),children:[TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'dz.sawt.aljazair'),MarkerLayer(markers:[Marker(point:selected,width:60,height:60,child:const Icon(Icons.location_pin,color:red,size:54))])]),
    Positioned(top:16,left:16,right:16,child:Card(child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[const Icon(Icons.touch_app,color:green),const SizedBox(width:8),Expanded(child:Text('اضغط على الخريطة لتحديد مكان وقوع الجريمة أو المشكلة.',style:const TextStyle(fontWeight:FontWeight.w700)))])))),
    Positioned(bottom:20,left:20,right:20,child:FilledButton.icon(onPressed:()=>Navigator.pop(context,selected),icon:const Icon(Icons.check),label:const Text('تأكيد هذا الموقع'),style:FilledButton.styleFrom(backgroundColor:green,padding:const EdgeInsets.all(16))))
  ]));
}

class ReportsPage extends StatefulWidget {const ReportsPage({super.key});@override State<ReportsPage> createState()=>_ReportsPageState();}
class _ReportsPageState extends State<ReportsPage>{
  List<Report> rows=[]; String? wilaya,type,status; final q=TextEditingController();
  Future<void> load()async{final params=<String>[];if(q.text.isNotEmpty)params.add('q=${Uri.encodeComponent(q.text)}');if(wilaya!=null)params.add('wilaya=${Uri.encodeComponent(wilaya!)}');if(type!=null)params.add('type=${Uri.encodeComponent(type!)}');if(status!=null)params.add('status=$status');final r=await api.get('/reports/search?${params.join('&')}');setState(()=>rows=(jsonDecode(r.body) as List).map((e)=>Report(Map<String,dynamic>.from(e))).toList());}
  @override void initState(){super.initState();load();}
  @override Widget build(BuildContext context)=>Column(children:[
    TopHeader(title:'البلاغات',subtitle:'بحث وفلترة البلاغات العامة'),
    Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:TextField(controller:q,onSubmitted:(_)=>load(),decoration:InputDecoration(hintText:'ابحث في العنوان والوصف',suffixIcon:IconButton(onPressed:load,icon:const Icon(Icons.search))))),
    SingleChildScrollView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.all(12),child:Row(children:[
      FilterChip(label:Text(wilaya??'كل الولايات'),selected:wilaya!=null,onSelected:(_)=>chooseWilaya()),
      const SizedBox(width:8),FilterChip(label:Text(type??'كل الأنواع'),selected:type!=null,onSelected:(_)=>chooseType()),
      const SizedBox(width:8),FilterChip(label:Text(status??'كل الحالات'),selected:status!=null,onSelected:(_)=>chooseStatus()),
    ])),
    Expanded(child:RefreshIndicator(onRefresh:load,child:ListView.builder(itemCount:rows.length,itemBuilder:(_,i)=>ReportTile(report:rows[i]))))
  ]);
  void chooseWilaya()=>showModalBottomSheet(context:context,builder:(_)=>ListView(children:[ListTile(title:const Text('كل الولايات'),onTap:(){setState(()=>wilaya=null);Navigator.pop(context);load();}),...wilayas.map((w)=>ListTile(title:Text(w),onTap:(){setState(()=>wilaya=w);Navigator.pop(context);load();}))]));
  void chooseType()=>showModalBottomSheet(context:context,builder:(_)=>ListView(children:[ListTile(title:const Text('كل الأنواع'),onTap:(){setState(()=>type=null);Navigator.pop(context);load();}),...reportTypes.map((w)=>ListTile(title:Text(w),onTap:(){setState(()=>type=w);Navigator.pop(context);load();}))]));
  void chooseStatus()=>showModalBottomSheet(context:context,builder:(_)=>ListView(children:['PENDING','REVIEWED','VERIFIED','RESOLVED','REJECTED'].map((s)=>ListTile(title:Text(s),onTap:(){setState(()=>status=s);Navigator.pop(context);load();})).toList()));
}

class ReportTile extends StatelessWidget {final Report report;const ReportTile({super.key,required this.report});
  @override Widget build(BuildContext context)=>Card(margin:const EdgeInsets.symmetric(horizontal:14,vertical:6),child:ListTile(
    leading:CircleAvatar(backgroundColor:report.status=='RESOLVED'?green:Colors.orange,child:const Icon(Icons.flag,color:Colors.white)),
    title:Text(report.title,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('${report.type} • ${report.wilaya}\n${report.description}',maxLines:2,overflow:TextOverflow.ellipsis),
    trailing:const Icon(Icons.chevron_right),onTap:()=>showModalBottomSheet(context:context,isScrollControlled:true,builder:(_)=>ReportDetails(report:report))));
}

class ReportDetails extends StatelessWidget {final Report report;const ReportDetails({super.key,required this.report});
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.all(18),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[const Icon(Icons.shield,color:green),const SizedBox(width:8),Expanded(child:Text(report.title,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900)))]),
    const SizedBox(height:10),Text(report.description),const SizedBox(height:10),
    Text('النوع: ${report.type}'),Text('الولاية: ${report.wilaya}'),Text('الحالة: ${report.status}'),
    if(report.media!=null)Padding(padding:const EdgeInsets.only(top:12),child:ClipRRect(borderRadius:BorderRadius.circular(16),child:Image.network(report.media!,height:220,width:double.infinity,fit:BoxFit.cover))),
    if(report.lat!=null&&report.lon!=null)...[
      Padding(padding:const EdgeInsets.only(top:12),child:FilledButton.icon(onPressed:()=>showModalBottomSheet(context:context,isScrollControlled:true,builder:(_)=>SizedBox(height:MediaQuery.of(context).size.height*.72,child:FlutterMap(options:MapOptions(initialCenter:LatLng(report.lat!,report.lon!),initialZoom:15),children:[TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'dz.sawt.aljazair'),MarkerLayer(markers:[Marker(point:LatLng(report.lat!,report.lon!),width:54,height:54,child:const Icon(Icons.location_pin,color:red,size:50))])]))),icon:const Icon(Icons.map_rounded),label:const Text('فتح الموقع على الخريطة'))),
      Padding(padding:const EdgeInsets.only(top:12),child:SizedBox(height:220,child:FlutterMap(options:MapOptions(initialCenter:LatLng(report.lat!,report.lon!),initialZoom:14),children:[
      TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'dz.sawt.aljazair'),
      MarkerLayer(markers:[Marker(point:LatLng(report.lat!,report.lon!),width:50,height:50,child:const Icon(Icons.location_pin,color:red,size:46))])
    ])))
  ]])));
}

class MapPage extends StatefulWidget {const MapPage({super.key});@override State<MapPage> createState()=>_MapPageState();}
class _MapPageState extends State<MapPage>{
  List<Report> reports=[];
  Future<void> load()async{try{final r=await api.get('/reports');setState(()=>reports=(jsonDecode(r.body) as List).map((e)=>Report(Map<String,dynamic>.from(e))).where((x)=>x.lat!=null&&x.lon!=null).toList());}catch(_){}} 
  @override void initState(){super.initState();load();}
  @override Widget build(BuildContext context)=>Column(children:[
    const TopHeader(title:'خريطة الجزائر',subtitle:'عرض تقريبي لمواقع البلاغات'),
    Expanded(child:FlutterMap(options:const MapOptions(initialCenter:LatLng(28.0339,1.6596),initialZoom:5),children:[
      TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'dz.sawt.aljazair'),
      MarkerLayer(markers:reports.map((r)=>Marker(point:LatLng(r.lat!,r.lon!),width:46,height:46,child:GestureDetector(onTap:()=>showModalBottomSheet(context:context,builder:(_)=>ReportDetails(report:r)),child:const Icon(Icons.location_pin,color:red,size:44)))).toList())
    ]))
  ]);
}

class MessagesPage extends StatefulWidget {const MessagesPage({super.key});@override State<MessagesPage> createState()=>_MessagesPageState();}
class _MessagesPageState extends State<MessagesPage>{
  List<dynamic> rows=[];
  Future<void> load()async{try{final r=await api.get('/conversations');setState(()=>rows=jsonDecode(r.body));}catch(_){}} 
  @override void initState(){super.initState();load();}
  @override Widget build(BuildContext context)=>Column(children:[
    const TopHeader(title:'المحادثات',subtitle:'تواصل داخل التطبيق مع أدوات الخصوصية'),
    Expanded(child:RefreshIndicator(onRefresh:load,child:ListView.builder(itemCount:rows.length,itemBuilder:(_,i){
      final members=rows[i]['members'] as List;final other=members.firstWhere((m)=>m['user']['id']!=null,orElse:()=>members.first);
      return ListTile(
        leading:const CircleAvatar(backgroundColor:green,child:Icon(Icons.person,color:Colors.white)),
        title:Text(other['user']['name']),subtitle:Text(rows[i]['lastMessage']?['body']??'ابدأ المحادثة'),
        onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ChatPage(conversationId:rows[i]['id'],title:other['user']['name']))).then((_){load();}));
    })))
  ]);
}

class ChatPage extends StatefulWidget {final String conversationId,title;const ChatPage({super.key,required this.conversationId,required this.title});@override State<ChatPage> createState()=>_ChatPageState();}
class _ChatPageState extends State<ChatPage>{
  List<dynamic> messages=[];final c=TextEditingController();io.Socket? socket;
  Future<void> load()async{final r=await api.get('/conversations/${widget.conversationId}/messages');setState(()=>messages=jsonDecode(r.body));await api.patchJson('/conversations/${widget.conversationId}/read',{});}
  @override void initState(){super.initState();load();socket=io.io(Api.base,io.OptionBuilder().setTransports(['websocket']).setAuth({'token':api.token}).build());socket!.on('connect',(_)=>socket!.emit('conversation:join',widget.conversationId));socket!.on('message:new',(m){if(m['conversationId']==widget.conversationId)setState(()=>messages.add(m));});}
  @override void dispose(){socket?.dispose();c.dispose();super.dispose();}
  Future<void> send()async{if(c.text.trim().isEmpty)return;final body=c.text.trim();c.clear();await api.postJson('/conversations/${widget.conversationId}/messages',{'body':body});}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.title),actions:[PopupMenuButton<String>(onSelected:(v){},itemBuilder:(_)=>const[PopupMenuItem(value:'mute',child:Text('كتم')),PopupMenuItem(value:'block',child:Text('حظر')),PopupMenuItem(value:'report',child:Text('إبلاغ'))])]),body:Column(children:[
    Expanded(child:ListView.builder(padding:const EdgeInsets.all(12),itemCount:messages.length,itemBuilder:(_,i){final mine=messages[i]['senderId']?.toString()==api.userId;return Align(alignment:mine?Alignment.centerRight:Alignment.centerLeft,child:Container(margin:const EdgeInsets.all(5),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:mine?green:Colors.white,borderRadius:BorderRadius.circular(18)),child:Text(messages[i]['body']??'',style:TextStyle(color:mine?Colors.white:ink))));})),
    SafeArea(child:Row(children:[Expanded(child:TextField(controller:c,decoration:const InputDecoration(hintText:'اكتب رسالة...'))),IconButton(onPressed:send,icon:const Icon(Icons.send,color:green))]))
  ]));
}

class ProfilePage extends StatefulWidget {const ProfilePage({super.key});@override State<ProfilePage> createState()=>_ProfilePageState();}
class _ProfilePageState extends State<ProfilePage>{
  User? user;
  Future<void> load()async{try{final r=await api.get('/me');setState(()=>user=User.fromJson((jsonDecode(r.body) as Map)['user']));}catch(_){}}
  @override void initState(){super.initState();load();}
  Future<void> openEdit()async{if(user==null)return;final updated=await Navigator.push<User>(context,MaterialPageRoute(builder:(_)=>EditProfilePage(user:user!)));if(updated!=null&&mounted)setState(()=>user=updated);}
  Future<void> contact(String value,{bool whatsapp=false})async{final digits=value.replaceAll(RegExp(r'[^0-9+]'),'');final normalized=digits.startsWith('+')?digits.substring(1):digits.startsWith('0')?'213${digits.substring(1)}':digits;final uri=whatsapp?Uri.parse('https://wa.me/$normalized'):Uri(scheme:'tel',path:value);if(await canLaunchUrl(uri))await launchUrl(uri,mode:LaunchMode.externalApplication);}
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(18),children:[
    TopHeader(title:'حسابي',subtitle:'إدارة ملفك ووسائل التواصل'),
    if(user!=null)Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(children:[
      Row(children:[CircleAvatar(radius:42,backgroundColor:green,backgroundImage:user!.avatarUrl!=null?NetworkImage(user!.avatarUrl!):null,child:user!.avatarUrl==null?Text(user!.name.isNotEmpty?user!.name.substring(0,1):'?',style:const TextStyle(color:Colors.white,fontSize:26,fontWeight:FontWeight.bold)):null),const SizedBox(width:15),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Flexible(child:Text(user!.name,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900))),if(user!.verified)const Icon(Icons.verified,color:green)]),Text('@${user!.username}'),Text(user!.wilaya??'الجزائر',style:const TextStyle(color:Colors.black54))]))]),
      if((user!.bio??'').isNotEmpty)Padding(padding:const EdgeInsets.only(top:12),child:Align(alignment:Alignment.centerRight,child:Text(user!.bio!))),
      if(user!.phone!=null||user!.whatsapp!=null)Padding(padding:const EdgeInsets.only(top:14),child:Wrap(spacing:8,runSpacing:8,children:[if(user!.phone!=null&&user!.phone!.isNotEmpty)OutlinedButton.icon(onPressed:()=>contact(user!.phone!),icon:const Icon(Icons.phone),label:const Text('اتصال')),if(user!.whatsapp!=null&&user!.whatsapp!.isNotEmpty)OutlinedButton.icon(onPressed:()=>contact(user!.whatsapp!,whatsapp:true),icon:const Icon(Icons.chat),label:const Text('واتساب'))])),
      const SizedBox(height:12),SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:openEdit,icon:const Icon(Icons.edit),label:const Text('تعديل الملف الشخصي')))
    ]))),
    const SizedBox(height:12),Card(child:Column(children:[
      ListTile(leading:const Icon(Icons.verified_user,color:green),title:const Text('طلب توثيق الحساب'),subtitle:const Text('التوثيق لا يعني اعتماد كل ما ينشره الحساب'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const VerificationPage()))),
      ListTile(leading:const Icon(Icons.search),title:const Text('المفقودات والمعثورات'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const LostFoundPage()))),
      if(user?.role=='ADMIN'||user?.role=='MODERATOR')ListTile(leading:const Icon(Icons.admin_panel_settings,color:green),title:const Text('لوحة المشرف'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const AdminPage()))),
      ListTile(leading:const Icon(Icons.info_outline),title:const Text('عن التطبيق'),onTap:()=>showAboutDialog(context:context,applicationName:'صوت الجزائر',applicationVersion:'1.5.6',children:[const Text('منصة مجتمعية للإبلاغ والمتابعة والمشاركة.')])),
      ListTile(leading:const Icon(Icons.logout,color:red),title:const Text('تسجيل الخروج'),onTap:()async{await api.clear();if(mounted)Navigator.pushAndRemoveUntil(context,MaterialPageRoute(builder:(_)=>const Welcome()),(_)=>false);})
    ]))
  ]);
}

class EditProfilePage extends StatefulWidget {final User user;const EditProfilePage({super.key,required this.user});@override State<EditProfilePage> createState()=>_EditProfilePageState();}
class _EditProfilePageState extends State<EditProfilePage>{
  late final TextEditingController name,bio,phone,whatsapp;late String wilaya;XFile? avatar;bool busy=false;
  @override void initState(){super.initState();name=TextEditingController(text:widget.user.name);bio=TextEditingController(text:widget.user.bio??'');phone=TextEditingController(text:widget.user.phone??'');whatsapp=TextEditingController(text:widget.user.whatsapp??'');wilaya=widget.user.wilaya??wilayas[30];}
  @override void dispose(){name.dispose();bio.dispose();phone.dispose();whatsapp.dispose();super.dispose();}
  Future<void> pickAvatar()async{final x=await ImagePicker().pickImage(source:ImageSource.gallery,imageQuality:85);if(x!=null)setState(()=>avatar=x);}
  Future<void> save()async{
    if(name.text.trim().isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('الاسم مطلوب')));return;}
    setState(()=>busy=true);
    try{
      final req=http.MultipartRequest('PATCH',Uri.parse('${Api.base}/me/profile'));
      req.headers.addAll(api.headers());
      req.fields.addAll({'displayName':name.text.trim(),'bio':bio.text.trim(),'phone':phone.text.trim(),'whatsapp':whatsapp.text.trim(),'wilaya':wilaya});
      if(avatar!=null)req.files.add(await http.MultipartFile.fromPath('avatar',avatar!.path));
      final r=await req.send();
      final body=await r.stream.bytesToString();
      Map<String,dynamic> decoded={};
      try{decoded=Map<String,dynamic>.from(jsonDecode(body) as Map);}catch(_){}
      if(r.statusCode>=400)throw Exception(decoded['error']?.toString()??'فشل حفظ الملف الشخصي (${r.statusCode})');
      final u=User.fromJson(Map<String,dynamic>.from(decoded['user'] as Map));
      if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم حفظ الملف الشخصي')));Navigator.pop(context,u);}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('تعديل الملف الشخصي')),body:ListView(padding:const EdgeInsets.all(18),children:[
    Center(child:Stack(children:[CircleAvatar(radius:54,backgroundColor:green,backgroundImage:avatar!=null?FileImage(File(avatar!.path)):widget.user.avatarUrl!=null?NetworkImage(widget.user.avatarUrl!):null,child:avatar==null&&widget.user.avatarUrl==null?Text(name.text.isNotEmpty?name.text.substring(0,1):'?',style:const TextStyle(color:Colors.white,fontSize:30)):null),Positioned(bottom:0,right:0,child:IconButton.filled(onPressed:pickAvatar,icon:const Icon(Icons.camera_alt)))])),
    const SizedBox(height:20),TextField(controller:name,decoration:const InputDecoration(labelText:'الاسم')),const SizedBox(height:10),TextField(controller:bio,maxLines:4,decoration:const InputDecoration(labelText:'النبذة التعريفية')),const SizedBox(height:10),DropdownButtonFormField(initialValue:wilaya,items:wilayas.map((w)=>DropdownMenuItem(value:w,child:Text(w))).toList(),onChanged:(v)=>setState(()=>wilaya=v!),decoration:const InputDecoration(labelText:'الولاية')),const SizedBox(height:10),TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'رقم الهاتف',prefixIcon:Icon(Icons.phone))),const SizedBox(height:10),TextField(controller:whatsapp,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'رقم واتساب',prefixIcon:Icon(Icons.chat))),const SizedBox(height:20),SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:busy?null:save,icon:const Icon(Icons.save),label:Text(busy?'جاري الحفظ...':'حفظ التغييرات'),style:FilledButton.styleFrom(backgroundColor:green,padding:const EdgeInsets.all(16))))
  ]));
}

class VerificationPage extends StatefulWidget {const VerificationPage({super.key});@override State<VerificationPage> createState()=>_VerificationPageState();}
class _VerificationPageState extends State<VerificationPage>{
  final reason=TextEditingController();XFile? doc;String? status;bool busy=false;
  Future<void> submit()async{setState(()=>busy=true);try{final req=http.MultipartRequest('POST',Uri.parse('${Api.base}/verification/request'));req.headers.addAll(api.headers());req.fields['reason']=reason.text;if(doc!=null)req.files.add(await http.MultipartFile.fromPath('document',doc!.path));final r=await req.send();if(r.statusCode>=400)throw Exception('تعذر إرسال الطلب');setState(()=>status='PENDING');}catch(e){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}finally{setState(()=>busy=false);}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('توثيق الحساب')),body:ListView(padding:const EdgeInsets.all(18),children:[
    const Text('اكتب سبب طلب التوثيق وأرفق مستندًا عند الحاجة. المراجعة تتم من حسابات مخولة.',style:TextStyle(fontSize:16)),
    const SizedBox(height:16),TextField(controller:reason,maxLines:5,decoration:const InputDecoration(labelText:'سبب الطلب')),
    const SizedBox(height:12),OutlinedButton.icon(onPressed:()async{final x=await ImagePicker().pickImage(source:ImageSource.gallery);if(x!=null)setState(()=>doc=x);},icon:const Icon(Icons.attach_file),label:Text(doc==null?'إرفاق مستند':'تم اختيار المستند')),
    const SizedBox(height:16),FilledButton(onPressed:busy?null:submit,child:Text(busy?'جاري الإرسال...':'إرسال الطلب')),
    if(status!=null)Padding(padding:const EdgeInsets.all(12),child:Text('الحالة: $status'))
  ]));
}

class LostFoundPage extends StatefulWidget {const LostFoundPage({super.key});@override State<LostFoundPage> createState()=>_LostFoundPageState();}
class _LostFoundPageState extends State<LostFoundPage>{
  List<dynamic> rows=[];String kind='LOST';final title=TextEditingController(),desc=TextEditingController(),cat=TextEditingController();String wilaya=wilayas[30];
  Future<void> load()async{final r=await api.get('/lost-found');setState(()=>rows=jsonDecode(r.body));}
  @override void initState(){super.initState();load();}
  Future<void> add()async{await api.postJson('/lost-found',{'kind':kind,'title':title.text,'description':desc.text,'category':cat.text,'wilaya':wilaya});title.clear();desc.clear();load();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('المفقودات والمعثورات')),body:Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Row(children:[ChoiceChip(label:const Text('مفقود'),selected:kind=='LOST',onSelected:(_)=>setState(()=>kind='LOST')),const SizedBox(width:8),ChoiceChip(label:const Text('معثور عليه'),selected:kind=='FOUND',onSelected:(_)=>setState(()=>kind='FOUND')),const Spacer(),IconButton(onPressed:()=>showDialog(context:context,builder:(_)=>AlertDialog(title:const Text('إضافة عنصر'),content:SingleChildScrollView(child:Column(children:[TextField(controller:title,decoration:const InputDecoration(labelText:'العنوان')),TextField(controller:cat,decoration:const InputDecoration(labelText:'الفئة')),DropdownButtonFormField(initialValue:wilaya,items:wilayas.map((w)=>DropdownMenuItem(value:w,child:Text(w))).toList(),onChanged:(v)=>wilaya=v!,decoration:const InputDecoration(labelText:'الولاية')),TextField(controller:desc,maxLines:3,decoration:const InputDecoration(labelText:'الوصف'))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('إلغاء')),FilledButton(onPressed:(){add();Navigator.pop(context);},child:const Text('حفظ'))])),icon:const Icon(Icons.add))])),
    Expanded(child:ListView.builder(itemCount:rows.length,itemBuilder:(_,i)=>ListTile(leading:CircleAvatar(backgroundColor:rows[i]['kind']=='FOUND'?green:red,child:Icon(rows[i]['kind']=='FOUND'?Icons.inventory_2:Icons.search,color:Colors.white)),title:Text(rows[i]['title']),subtitle:Text('${rows[i]['category']} • ${rows[i]['wilaya']}'))))
  ]));
}

class AdminPage extends StatefulWidget {const AdminPage({super.key});@override State<AdminPage> createState()=>_AdminPageState();}
class _AdminPageState extends State<AdminPage>{
  Map<String,dynamic> stats={};List<dynamic> reports=[];
  Future<void> load()async{final a=await api.get('/admin/stats');final b=await api.get('/admin/reports');setState((){stats=jsonDecode(a.body);reports=jsonDecode(b.body);});}
  @override void initState(){super.initState();load();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('لوحة المشرف')),body:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
    GridView.count(shrinkWrap:true,crossAxisCount:2,physics:const NeverScrollableScrollPhysics(),childAspectRatio:1.7,children:stats.entries.map((e)=>Card(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('${e.value}',style:const TextStyle(fontSize:25,fontWeight:FontWeight.w900,color:green)),Text(e.key)]))).toList()),
    const SizedBox(height:10),const Text('مراجعة البلاغات',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
    ...reports.map((r)=>Card(child:ListTile(title:Text(r['title']),subtitle:Text('${r['wilaya']} • ${r['status']}'),trailing:PopupMenuButton<String>(onSelected:(s)async{await api.patchJson('/reports/${r['id']}/status',{'status':s});load();},itemBuilder:(_)=>const[PopupMenuItem(value:'REVIEWED',child:Text('قيد المراجعة')),PopupMenuItem(value:'VERIFIED',child:Text('تم التحقق')),PopupMenuItem(value:'RESOLVED',child:Text('تمت المعالجة')),PopupMenuItem(value:'REJECTED',child:Text('مرفوض'))]))))
  ])));
}

class UserSearchDelegate extends SearchDelegate<String>{
  @override List<Widget>? buildActions(BuildContext context)=>[IconButton(onPressed:()=>query='',icon:const Icon(Icons.clear))];
  @override Widget? buildLeading(BuildContext context)=>IconButton(onPressed:()=>close(context,''),icon:const Icon(Icons.arrow_back));
  @override Widget buildResults(BuildContext context)=>FutureBuilder<http.Response>(future:api.get('/users/search?q=${Uri.encodeComponent(query)}'),builder:(_,s){
    if(!s.hasData)return const Center(child:CircularProgressIndicator());final rows=jsonDecode(s.data!.body) as List;return ListView(children:rows.map((u)=>ListTile(leading:const CircleAvatar(backgroundColor:green,child:Icon(Icons.person,color:Colors.white)),title:Text(u['name']),subtitle:Text('@${u['username']}'),trailing:u['isVerified']==true?const Icon(Icons.verified,color:green):null)).toList());
  });
  @override Widget buildSuggestions(BuildContext context)=>const Center(child:Text('ابحث عن حساب'));
}
