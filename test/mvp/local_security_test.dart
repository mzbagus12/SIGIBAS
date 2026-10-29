import 'package:flutter_test/flutter_test.dart';
import 'package:sigibas_rasp/mvp/local_security.dart';
void main(){
  test('local Android policy blocks root/emulator/hook/signature in all modes',(){
    for(final finding in ['root','emulator','hook','signature']) {
      expect(evaluateLocalSecurity({finding:true},debugMode:true),contains(finding));
      expect(evaluateLocalSecurity({finding:true},debugMode:false),contains(finding));
    }
    expect(evaluateLocalSecurity({'debugger':true},debugMode:true),isEmpty);
    expect(evaluateLocalSecurity({'debugger':true},debugMode:false),contains('debugger'));
    expect(evaluateLocalSecurity({'root':false,'signature':false},debugMode:false),isEmpty);
  });
}
