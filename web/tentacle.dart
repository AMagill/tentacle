import 'dart:html';
import 'dart:web_gl' as webgl;
import 'package:vector_math/vector_math.dart';

class TentacleScene {
  int _width, _height;
  webgl.RenderingContext _gl;
  List<Tentacle> tentacles;
  
  TentacleScene(CanvasElement canvas) {
    _width  = canvas.width;
    _height = canvas.height;
    _gl     = canvas.getContext("experimental-webgl");
    
    tentacles = new List<Tentacle>();
    tentacles.add(new Tentacle(1.0, 4));
  }
  
  void render() {
    _gl.clearColor(1, 0, 0, 1);
    _gl.clear(webgl.COLOR_BUFFER_BIT);
    
    
  }
    
}

class Tentacle {
  double _length;
  int _nSegments;
  var _segVel, _segRot, _segPos;
    
  Tentacle(this._length, this._nSegments) {
    _segVel = new List.filled(_nSegments, new Vector3.zero());
    _segRot = new List.filled(_nSegments, new Vector3.zero());
    _segPos = new List.filled(_nSegments, new Vector3.zero());
    
    _calcAbsPos();
  }
  
  void _calcAbsPos() {
    final segLen = _length / _nSegments;
    Matrix4 transform = new Matrix4.identity();
    
    for (var i = 0; i < _nSegments; i++) {
      transform.translate(0.0, 0.0, segLen);
      transform.rotate3(_segRot[i]);
      _segPos[i] = transform.getTranslation();
    }
  }
}



void main() {
  var canvas = document.querySelector("#glCanvas");
  var scene = new TentacleScene(canvas);

  window.animationFrame
    .then((time) => scene.render());
}
