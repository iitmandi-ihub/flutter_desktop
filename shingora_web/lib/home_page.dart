
import 'package:flutter/material.dart';


class HomePage extends StatefulWidget{

  const HomePage({super.key});

  @override
  State<StatefulWidget> createState() {
   return _HomePageState();
  }

}

class _HomePageState  extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
   return Scaffold(
     appBar: AppBar(title: Text("my web app"),backgroundColor:Colors.blue,),
     body: Center(
       child: Row(
         children: [
           Expanded(
             flex: 1,
          child: Container(color: Colors.blue, height: 50),),
           Expanded(
             flex: 1,
             child: Column(
               children: [
                 ElevatedButton(onPressed:(){

                 },
                     child:Text("Capture Image by Camera")),
                 SizedBox(height: 10,),
                 ElevatedButton(onPressed:(){},
                     child:Text("Get Result")),
               ],
             ),
           )
         ],
       ),
     ),
   );
  }

}