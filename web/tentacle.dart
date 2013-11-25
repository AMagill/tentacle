import 'dart:html';
import 'dart:web_gl' as webgl;
import 'dart:typed_data';
import 'package:vector_math/vector_math.dart';
import 'shader.dart';

class TentacleScene {
  int _width, _height;
  webgl.RenderingContext _gl;
  Shader _objShader;
  List<Tentacle> tentacles;
  
  TentacleScene(CanvasElement canvas) {
    _width  = canvas.width;
    _height = canvas.height;
    _gl     = canvas.getContext("experimental-webgl");
    
    tentacles = new List<Tentacle>();
    tentacles.add(new Tentacle(_gl, 1.0, 4));
    
    _initShaders();
    _gl.clearColor(0.1, 0, 0, 1);
    _gl.viewport(0, 0, _width, _height);
  }
  
  void _initShaders() {
    String vsObject = """
precision mediump int;
precision mediump float;

attribute vec3 aPosition;

uniform mat4 uProjection;
uniform mat4 uModelView;

void main() {
  gl_Position = uProjection * uModelView * vec4(aPosition, 1.0);
}
    """;
    
    String fsObject = """
precision mediump int;
precision mediump float;

void main() {
  gl_FragColor = vec4(0.0, 1.0, 0.0, 1.0);
}
    """;
    
    _objShader = new Shader(_gl, vsObject, fsObject, {'aPosition': 0});
  }
  
  void render() {
    _gl.clear(webgl.COLOR_BUFFER_BIT);
    
    var mProjection = makeOrthographicMatrix(-1, 1, 0, 2, -1, 1);
    var mModelView  = new Matrix4.identity(); 
    
    _objShader.use();
    _gl.uniformMatrix4fv(_objShader['uProjection'], false, mProjection.storage);
    _gl.uniformMatrix4fv(_objShader['uModelView'],  false, mModelView.storage);
    
    _gl.lineWidth(10.0);
    for (var tentacle in tentacles) {
      tentacle.bind();
      tentacle.draw(mode: webgl.LINE_STRIP);
    }
  }
    
}

class Tentacle {
  webgl.RenderingContext _gl;
  webgl.Buffer _vbo;
  double _length;
  int _nSegments;
  var _segVel, _segRot, _segPos;
    
  Tentacle(this._gl, this._length, this._nSegments) {
    _vbo = _gl.createBuffer();
    
    _segVel = new List.filled(_nSegments, new Vector3.zero());
    _segRot = new List.filled(_nSegments, new Vector3(0.1,0.0,0.0));//.zero());
    _segPos = new List.filled((_nSegments + 1) * 3, 0.0);
    
    update();
  }
  
  void update() {
    final segLen = _length / _nSegments;
    Matrix4 transform = new Matrix4.identity();
    
    for (var i = 0; i < _nSegments; i++) {
      transform.translate(0.0, segLen, 0.0);
      transform.rotateX(_segRot[i].x);
      transform.rotateY(_segRot[i].y);
      transform.rotateZ(_segRot[i].z);
      var trans = transform * new Vector4(0.0,0.0,0.0,1.0);
      _segPos[i*3 + 3] = trans[0];
      _segPos[i*3 + 4] = trans[1];
      _segPos[i*3 + 5] = trans[2];
    }
    
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vbo);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, 
        new Float32List.fromList(_segPos), webgl.DYNAMIC_DRAW);
  }
  
  void bind() {
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vbo);
    _gl.vertexAttribPointer(0, 3, webgl.FLOAT, false, 0, 0);
    _gl.enableVertexAttribArray(0);
  }
  
  void draw({mode: webgl.LINE_STRIP}) {
    _gl.drawArrays(mode, 0, _nSegments+1);
  }
}



void main() {
  var canvas = document.querySelector("#glCanvas");
  var scene = new TentacleScene(canvas);
  
  window.onClick.listen((event) => scene.render());

  window.animationFrame
    .then((time) => scene.render());
}
