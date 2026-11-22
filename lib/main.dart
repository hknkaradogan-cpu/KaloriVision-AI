import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KaloriVisionApp());
}

class Meal {
  final String name, date;
  final int calories;
  final double protein, carbs, fat;
  const Meal(this.name, this.date, this.calories, this.protein, this.carbs, this.fat);
  Map<String,dynamic> toJson() => {'name':name,'date':date,'calories':calories,'protein':protein,'carbs':carbs,'fat':fat};
  factory Meal.fromJson(Map<String,dynamic> j) => Meal(j['name'] ?? 'Öğün', j['date'] ?? '', (j['calories'] as num? ?? 0).round(), (j['protein'] as num? ?? 0).toDouble(), (j['carbs'] as num? ?? 0).toDouble(), (j['fat'] as num? ?? 0).toDouble());
}

class KaloriVisionApp extends StatelessWidget {
  const KaloriVisionApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner:false,
    title:'KaloriVision AI',
    theme:ThemeData(useMaterial3:true, colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xff16866b)), scaffoldBackgroundColor:const Color(0xfff4f8f6)),
    home:const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState()=>_HomePageState();
}
class _HomePageState extends State<HomePage> {
  final picker=ImagePicker();
  final name=TextEditingController(), kcal=TextEditingController(), protein=TextEditingController(), carbs=TextEditingController(), fat=TextEditingController(), goalInput=TextEditingController(), keyInput=TextEditingController();
  List<Meal> meals=[];
  int goal=2000, tab=0;
  String apiKey='';
  bool busy=false;
  String get today=>DateTime.now().toIso8601String().substring(0,10);
  List<Meal> get todays=>meals.where((m)=>m.date==today).toList();
  int get total=>todays.fold(0,(s,m)=>s+m.calories);
  double get prot=>todays.fold(0.0,(s,m)=>s+m.protein);
  double get carb=>todays.fold(0.0,(s,m)=>s+m.carbs);
  double get fatTotal=>todays.fold(0.0,(s,m)=>s+m.fat);

  @override void initState(){super.initState();load();}
  Future<void> load() async {
    final s=await SharedPreferences.getInstance();
    if(!mounted)return;
    setState((){
      meals=(s.getStringList('meals')??[]).map((e)=>Meal.fromJson(jsonDecode(e))).toList();
      goal=s.getInt('goal')??2000;
      apiKey=s.getString('gemini_key')??'';
    });
  }
  Future<void> saveMeals() async {
    final s=await SharedPreferences.getInstance();
    await s.setStringList('meals',meals.map((m)=>jsonEncode(m.toJson())).toList());
  }
  Future<void> add(Meal m) async {setState(()=>meals.insert(0,m));await saveMeals();}
  void msg(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));
  Widget field(TextEditingController c,String label,{bool number=false})=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(controller:c,keyboardType:number?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder())));

  Future<void> manual() async {
    name.clear();kcal.clear();protein.text='0';carbs.text='0';fat.text='0';
    await showDialog(context:context,builder:(d)=>AlertDialog(
      title:const Text('Öğün ekle'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[field(name,'Yemek adı'),field(kcal,'Kalori (kcal)',number:true),field(protein,'Protein (g)',number:true),field(carbs,'Karbonhidrat (g)',number:true),field(fat,'Yağ (g)',number:true)])),
      actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('İptal')),FilledButton(onPressed:(){
        final n=int.tryParse(kcal.text);
        if(name.text.trim().isEmpty||n==null){msg('Yemek adı ve kalori gir.');return;}
        add(Meal(name.text.trim(),today,n,double.tryParse(protein.text)??0,double.tryParse(carbs.text)??0,double.tryParse(fat.text)??0));
        Navigator.pop(d);
      },child:const Text('Kaydet'))],
    ));
  }

  Future<void> analyze() async {
    if(apiKey.trim().isEmpty){msg('Önce Ayarlar bölümüne Gemini API anahtarını ekle.');return;}
    final file=await picker.pickImage(source:ImageSource.gallery,imageQuality:80,maxWidth:1500);
    if(file==null)return;
    setState(()=>busy=true);
    try{
      final bytes=await File(file.path).readAsBytes();
      final mime=file.path.toLowerCase().endsWith('.png')?'image/png':'image/jpeg';
      final uri=Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key='+apiKey.trim());
      final response=await http.post(uri,headers:{'Content-Type':'application/json'},body:jsonEncode({
        'contents':[{'parts':[
          {'text':'Yemeği Türkçe analiz et. Sadece JSON döndür: {"name":"yemek adı","portion":"porsiyon","calories":400,"protein":20,"carbs":35,"fat":15,"note":"tahmin notu"}. Sayısal alanlar sayı olsun. Değerler yaklaşık tahmindir.'},
          {'inline_data':{'mime_type':mime,'data':base64Encode(bytes)}}
        ]}]
      }));
      if(response.statusCode<200||response.statusCode>=300)throw Exception('Gemini HTTP '+response.statusCode.toString());
      final body=jsonDecode(response.body);
      final raw=(body['candidates'][0]['content']['parts'] as List).map((e)=>e['text']??'').join();
      final clean=raw.replaceAll('''' + '```json' + '''','').replaceAll('''' + '```' + '''','').trim();
      final a=jsonDecode(clean) as Map<String,dynamic>;
      if(!mounted)return;
      await showDialog(context:context,builder:(d)=>AlertDialog(
        title:Text(a['name']??'Yemek analizi'),
        content:Text('Porsiyon: '+(a['portion']??'Tahmini').toString()+'\nKalori: '+a['calories'].toString()+' kcal\nProtein: '+a['protein'].toString()+' g\nKarbonhidrat: '+a['carbs'].toString()+' g\nYağ: '+a['fat'].toString()+' g\n\n'+(a['note']??'Değerler tahminidir.').toString()),
        actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Kapat')),FilledButton(onPressed:(){
          Navigator.pop(d);
          add(Meal(a['name']??'Yemek',today,(a['calories'] as num).round(),(a['protein'] as num).toDouble(),(a['carbs'] as num).toDouble(),(a['fat'] as num).toDouble()));
        },child:const Text('Günlüğe ekle'))],
      ));
    }catch(e){msg('Fotoğraf analizi başarısız: '+e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> barcode() async {
    final code=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>const BarcodePage()));
    if(code==null||code.isEmpty)return;
    setState(()=>busy=true);
    try{
      final r=await http.get(Uri.parse('https://world.openfoodfacts.org/api/v2/product/'+code+'.json'));
      final j=jsonDecode(r.body);
      if(r.statusCode!=200||j['status']!=1||j['product']==null){msg('Ürün bulunamadı.');return;}
      final product=j['product'] as Map<String,dynamic>;
      final n=product['nutriments']??{};
      final cal=(n['energy-kcal_100g'] as num? ?? 0).round();
      final pr=(n['proteins_100g'] as num? ?? 0).toDouble();
      final cb=(n['carbohydrates_100g'] as num? ?? 0).toDouble();
      final ft=(n['fat_100g'] as num? ?? 0).toDouble();
      if(!mounted)return;
      await showDialog(context:context,builder:(d)=>AlertDialog(
        title:Text(product['product_name']??'Barkod ürünü'),
        content:Text('100 g için: '+cal.toString()+' kcal\nProtein '+pr.toString()+' g · Karbonhidrat '+cb.toString()+' g · Yağ '+ft.toString()+' g'),
        actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Kapat')),FilledButton(onPressed:(){Navigator.pop(d);add(Meal(product['product_name']??'Paketli ürün',today,cal,pr,cb,ft));},child:const Text('100 g ekle'))],
      ));
    }catch(e){msg('Barkod sorgusu başarısız: '+e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }

  Future<void> settings() async {
    goalInput.text=goal.toString();keyInput.text=apiKey;
    await showDialog(context:context,builder:(d)=>AlertDialog(
      title:const Text('Ayarlar'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        field(goalInput,'Günlük kalori hedefi',number:true),
        TextField(controller:keyInput,obscureText:true,decoration:const InputDecoration(labelText:'Gemini API anahtarı',border:OutlineInputBorder(),helperText:'Fotoğraf analizi için gereklidir')),
        const SizedBox(height:10),
        const SelectableText('API anahtarı: https://aistudio.google.com/app/apikey'),
        const Text('Fotoğrafı analiz etmeyi seçtiğinde görsel Gemini servisine gönderilir. Sonuçlar tahmindir.',style:TextStyle(fontSize:12)),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('İptal')),FilledButton(onPressed:()async{
        final s=await SharedPreferences.getInstance();
        final g=int.tryParse(goalInput.text);
        if(g!=null&&g>0){goal=g;await s.setInt('goal',goal);}
        apiKey=keyInput.text.trim();await s.setString('gemini_key',apiKey);
        if(mounted){Navigator.pop(d);setState((){});msg('Ayarlar kaydedildi.');}
      },child:const Text('Kaydet'))],
    ));
  }

  @override void dispose(){name.dispose();kcal.dispose();protein.dispose();carbs.dispose();fat.dispose();goalInput.dispose();keyInput.dispose();super.dispose();}

  @override Widget build(BuildContext context){
    final pages=[dashboard(),history(),settingsPage()];
    return Scaffold(
      appBar:AppBar(title:Row(children:[
        Container(width:38,height:38,decoration:BoxDecoration(color:Theme.of(context).colorScheme.primary,borderRadius:BorderRadius.circular(12)),child:const Icon(Icons.restaurant,color:Colors.white)),
        const SizedBox(width:10),
        const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('KaloriVision AI',style:TextStyle(fontWeight:FontWeight.bold)),Text('Beslenme yol arkadaşın',style:TextStyle(fontSize:11))]),
      ]),actions:[IconButton(onPressed:settings,icon:const Icon(Icons.tune))]),
      body:SafeArea(child:pages[tab]),
      floatingActionButton:tab==0?FloatingActionButton.extended(onPressed:manual,icon:const Icon(Icons.add),label:const Text('Öğün ekle')):null,
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[
        NavigationDestination(icon:Icon(Icons.home_outlined),label:'Bugün'),
        NavigationDestination(icon:Icon(Icons.history),label:'Geçmiş'),
        NavigationDestination(icon:Icon(Icons.settings_outlined),label:'Ayarlar'),
      ]),
    );
  }

  Widget dashboard()=>ListView(padding:const EdgeInsets.fromLTRB(16,14,16,100),children:[
    Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xff13765f),Color(0xff2ba789)]),borderRadius:BorderRadius.circular(24)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('BUGÜNÜN ÖZETİ',style:TextStyle(color:Colors.white70,letterSpacing:1)),
      const SizedBox(height:12),
      Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
        Text(total.toString(),style:const TextStyle(color:Colors.white,fontSize:42,fontWeight:FontWeight.bold)),
        const Padding(padding:EdgeInsets.only(bottom:8,left:6),child:Text('kcal alındı',style:TextStyle(color:Colors.white70))),
        const Spacer(),
        Text((goal-total).clamp(0,goal).toString()+' kcal kaldı',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w600)),
      ]),
      const SizedBox(height:12),
      ClipRRect(borderRadius:BorderRadius.circular(20),child:LinearProgressIndicator(value:(total/goal).clamp(0.0,1.0),minHeight:10,backgroundColor:Colors.white30,color:Colors.white)),
      const SizedBox(height:8),
      Text('Günlük hedef: '+goal.toString()+' kcal',style:const TextStyle(color:Colors.white70)),
    ])),
    const SizedBox(height:20),
    const Text('Makro besinler',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    const SizedBox(height:10),
    Row(children:[macro('Protein',prot),const SizedBox(width:8),macro('Karbonhidrat',carb),const SizedBox(width:8),macro('Yağ',fatTotal)]),
    const SizedBox(height:22),
    const Text('Hızlı işlemler',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    const SizedBox(height:10),
    Row(children:[Expanded(child:quick(Icons.photo_camera_outlined,'Fotoğraftan analiz',analyze)),const SizedBox(width:10),Expanded(child:quick(Icons.qr_code_scanner,'Barkod tara',barcode))]),
    const SizedBox(height:22),
    const Text('Bugünkü öğünlerin',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    const SizedBox(height:8),
    if(todays.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(24),child:Column(children:[Icon(Icons.restaurant_menu,size:38,color:Colors.grey),SizedBox(height:8),Text('Henüz öğün eklemedin'),Text('Fotoğrafla analiz et veya manuel ekle.',style:TextStyle(color:Colors.grey))])))
    else ...todays.map(mealTile),
    if(busy)const Padding(padding:EdgeInsets.all(18),child:Center(child:CircularProgressIndicator())),
  ]);
  Widget macro(String label,double value)=>Expanded(child:Card(elevation:0,child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(value.toStringAsFixed(0)+' g',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17)),Text(label,style:const TextStyle(fontSize:11,color:Colors.grey))]))));
  Widget quick(IconData icon,String label,VoidCallback action)=>InkWell(onTap:busy?null:action,borderRadius:BorderRadius.circular(16),child:Card(elevation:0,child:Padding(padding:const EdgeInsets.symmetric(vertical:18,horizontal:8),child:Column(children:[Icon(icon,size:28,color:Theme.of(context).colorScheme.primary),const SizedBox(height:8),Text(label,textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w600,fontSize:12))]))));
  Widget mealTile(Meal m)=>Card(elevation:0,child:ListTile(leading:const CircleAvatar(child:Icon(Icons.restaurant)),title:Text(m.name),subtitle:Text('P: '+m.protein.toString()+' g · K: '+m.carbs.toString()+' g · Y: '+m.fat.toString()+' g'),trailing:Text(m.calories.toString()+' kcal',style:const TextStyle(fontWeight:FontWeight.bold))));
  Widget history()=>ListView(padding:const EdgeInsets.all(16),children:[const Text('Öğün geçmişi',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:12),if(meals.isEmpty)const Text('Henüz kayıt yok.'),...meals.map(mealTile)]);
  Widget settingsPage()=>ListView(padding:const EdgeInsets.all(16),children:[
    const Text('Ayarlar',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
    Card(child:ListTile(leading:const Icon(Icons.flag_outlined),title:const Text('Günlük kalori hedefi'),subtitle:Text(goal.toString()+' kcal'),trailing:const Icon(Icons.chevron_right),onTap:settings)),
    Card(child:ListTile(leading:const Icon(Icons.key_outlined),title:const Text('Gemini API anahtarı'),subtitle:Text(apiKey.isEmpty?'Eklenmedi':'Kaydedildi'),trailing:const Icon(Icons.chevron_right),onTap:settings)),
    const Card(child:ListTile(leading:Icon(Icons.privacy_tip_outlined),title:Text('Gizlilik'),subtitle:Text('Öğünler cihazda saklanır. Fotoğraf yalnızca analiz isteğinde Gemini servisine gönderilir.'))),
    const Card(child:ListTile(leading:Icon(Icons.info_outline),title:Text('Bilgilendirme'),subtitle:Text('Kalori değerleri tahmindir, tıbbi tavsiye değildir.'))),
  ]);
}

class BarcodePage extends StatefulWidget {
  const BarcodePage({super.key});
  @override State<BarcodePage> createState()=>_BarcodePageState();
}
class _BarcodePageState extends State<BarcodePage>{
  bool found=false;
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Barkod tara')),
    body:MobileScanner(onDetect:(capture){
      if(found)return;
      final code=capture.barcodes.isNotEmpty?capture.barcodes.first.rawValue:null;
      if(code!=null&&code.isNotEmpty){found=true;Navigator.pop(context,code);}
    }),
  );
}
