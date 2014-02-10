import 'dart:html';
import 'dart:web_gl' as webgl;
import 'dart:typed_data';
import 'dart:math';
import 'package:vector_math/vector_math.dart';
import 'package:noise/noise.dart';
import 'shader.dart';

class TentacleScene {
  final int NBONES = 6;
  int _width, _height;
  webgl.RenderingContext _gl;
  Shader _objShader;
  List<Tentacle> tentacles;
  
  TentacleScene(CanvasElement canvas) {
    _width  = canvas.width;
    _height = canvas.height;
    _gl     = canvas.getContext("experimental-webgl");
    
    tentacles = new List<Tentacle>();
    tentacles.add(new Tentacle(_gl, 1.0, NBONES));
    
    _initShaders();
    _gl.enable(webgl.DEPTH_TEST);
    _gl.clearColor(0.0, 0, 0, 1);
    _gl.viewport(0, 0, _width, _height);
  }
  
  void _initShaders() {
    String vsObject = """
precision mediump int;
precision mediump float;

const int NBONES = $NBONES;

attribute vec3  aPosition;
attribute vec3  aNormal;
attribute vec2  aTexture;
attribute float aBonePos;

uniform mat4 uProjection;
uniform mat4 uModelView;
uniform vec2 uBone[NBONES];

varying vec4 color;

void main() {
  const float off = 1.0 / float(NBONES);

  mat4  boneMat = mat4(1.0);
  for (int i = NBONES-1; i >= 0; i--) {
    float influence = clamp(aBonePos - float(i-1), 0.0, 1.0);
    float rx = uBone[i].x * influence;
    float ry = uBone[i].y * influence;

    // Translate the root of the bone to the origin
    boneMat *= mat4(
      1.0,0.0,0.0,0.0,
      0.0,1.0,0.0,0.0,
      0.0,0.0,1.0,0.0,
      0.0,-off*float(i),0.0,1.0);
    // Rotate about X
    mat4 rotMat = mat4(
      1.0, 0.0, 0.0, 0.0,
      0.0, cos(ry), -sin(ry), 0.0,
      0.0, sin(ry),  cos(ry), 0.0,
      0.0, 0.0, 0.0, 1.0);
    // Rotate about Z
    rotMat *= mat4(
      cos(rx), -sin(rx), 0.0, 0.0,
      sin(rx),  cos(rx), 0.0, 0.0,
      0.0, 0.0, 1.0, 0.0,
      0.0, 0.0, 0.0, 1.0);
    boneMat *= rotMat;
    // Translate back to the proper place
    boneMat *= mat4(
      1.0,0.0,0.0,0.0,
      0.0,1.0,0.0,0.0,
      0.0,0.0,1.0,0.0,
      0.0,off*float(i),0.0,1.0);
  }

  gl_Position = uProjection * uModelView * boneMat * vec4(aPosition, 1.0);
  gl_PointSize = 3.0;

  color = vec4(aNormal, 1.0);
  //color = vec4(aTexture, 0.0, 1.0);
}
    """;
    
    String fsObject = """
precision mediump int;
precision mediump float;

varying vec4 color;

void main() {
  gl_FragColor = color;//vec4(0.0, 1.0, 0.0, 1.0);
}
    """;
    
    _objShader = new Shader(_gl, vsObject, fsObject, 
        {'aPosition': 0, 'aNormal': 1, 'aTexture': 2, 'aBonePos': 3});
  }
  
  void animate(double time) {
    for (var tentacle in tentacles) {
      tentacle.animate(time);
    }
    //tentacles[0]._segRot[2] = PI/2;
  }
  
  void render() {
    _gl.clear(webgl.COLOR_BUFFER_BIT);
    
    var mProjection = makeOrthographicMatrix(-1, 1, -0.2, 1.8, -2, 2);
    var mModelView  = new Matrix4.identity().scale(2.0);
    
    _objShader.use();
    _gl.uniformMatrix4fv(_objShader['uProjection'], false, mProjection.storage);
    _gl.uniformMatrix4fv(_objShader['uModelView'],  false, mModelView.storage);
    
    
    for (var tentacle in tentacles) {
      _gl.uniform2fv(_objShader['uBone[0]'], tentacle._segRot);
      tentacle.bind();
      tentacle.draw();
    }
  }
    
}

class Tentacle {
  webgl.RenderingContext _gl;
  webgl.Buffer _vboPos, _vboNrm, _vboTex, _vboBnP, _ibo;
  double _length;
  int _nBones;
  int _nIndices = 0;
  var _segVel, _segRot, _segPos;
    
  Tentacle(this._gl, this._length, this._nBones) {
    _vboPos = _gl.createBuffer();
    _vboNrm = _gl.createBuffer();
    _vboTex = _gl.createBuffer();
    _vboBnP = _gl.createBuffer();
    _ibo    = _gl.createBuffer();
    generateGeometry();
    
    _segVel = new Float32List(_nBones * 2);
    _segRot = new Float32List(_nBones * 2);
  }
  
  void animate(double time) {
    for (var i = 1; i  < _nBones; i++) {
      var fx = simplex2(time / 10000, i / 10);
      var fy = simplex2(i / 10, time / 10000);
      var rot = new Vector3(fx, 0.0, fy) * ((i+1) / _nBones) * 0.6;
      _segRot[i*2+0] += rot.x;
      _segRot[i*2+1] += rot.z;
      _segRot[i*2+0] *= 0.8;
      _segRot[i*2+1] *= 0.8;
    }
  }
  
  void bind() {
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboPos);
    _gl.vertexAttribPointer(0, 3, webgl.FLOAT, false, 0, 0);
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboNrm);
    _gl.vertexAttribPointer(1, 3, webgl.FLOAT, false, 0, 0);
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboTex);
    _gl.vertexAttribPointer(2, 2, webgl.FLOAT, false, 0, 0);
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboBnP);
    _gl.vertexAttribPointer(3, 1, webgl.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.ELEMENT_ARRAY_BUFFER, _ibo);

    _gl.enableVertexAttribArray(0);
    _gl.enableVertexAttribArray(1);
    _gl.enableVertexAttribArray(2);
    _gl.enableVertexAttribArray(3);
  }
  
  void draw() {
    //_gl.drawElements(webgl.TRIANGLES, _nIndices, webgl.UNSIGNED_SHORT, 0);
    _gl.drawElements(webgl.LINE_STRIP, _nIndices, webgl.UNSIGNED_SHORT, 0);
  }
  
  void generateGeometry() {
    var vertPos = new List<double>();
    var vertNrm = new List<double>();
    var vertTex = new List<double>();
    var vertBnP = new List<double>();
    var indices = new List<int>();
    
    // Generate skeleton
    /*vertPos.addAll([0.0, 0.0, 0.0]);
    vertBnP.add(0.0);
    for (var i = 0; i < _nBones; i++) {
      vertPos.addAll([0.0, (i+1)*(1.0/_nBones), 0.0]);
      vertBnP.add(i.toDouble());
      indices.addAll([i, i+1]);
    }*/
    
    // Generate body
    final nLoops = 30;
    final nSides = 16;
    final radsPerSide = 2.0*PI/nSides;
    for (var i = 0; i < nLoops; i++) {
      final bonePos = i / (nLoops-1) * _nBones - 0.5;
      final radius = 0.1 * sqrt((nLoops-i)/nLoops);      
      for (var j = 0; j < nSides; j++) {
        vertPos.addAll([radius*sin(j*radsPerSide),   i / (nLoops-1),
                        radius*cos(j*radsPerSide)]);
        vertBnP.add(bonePos.clamp(0.0, _nBones-1.0));
        final ny = 0.1/sqrt((nLoops-i)/nLoops);
        final nr = 1.0-ny*ny;
        vertNrm.addAll([nr*sin(j*radsPerSide),    ny,
                        nr*cos(j*radsPerSide)]);
        vertTex.addAll([j / (nSides-1), i / (nLoops-1)]);
        
        if (i != 0) {
          final tl = vertPos.length ~/ 3 - 1;
          final tr = (nSides-j > 1) ? (tl+1) : (tl+1-nSides);
          final bl = tl - nSides, br = tr - nSides; 
          indices.addAll([bl, br, tl,    br, tr, tl]);
        }
      }
    }
    // Add geometry for a tip converging to a point
    vertPos.addAll([0.0, 1.0 + 0.3/nLoops, 0.0]);
    vertBnP.add(_nBones.toDouble());
    vertNrm.addAll([0.0, 1.0, 0.0]);
    vertTex.addAll([0.5, 1.0]);
    final t = vertPos.length ~/ 3 - 1;
    for (var j = 0; j < nSides; j++) {
      final l = t - nSides + j;
      final r = (nSides-j > 1) ? (l+1) : (l+1-nSides);
      indices.addAll([l, r, t]);
    }
    
    // Buffer geometry
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboPos);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, 
        new Float32List.fromList(vertPos), webgl.STATIC_DRAW);
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboNrm);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, 
        new Float32List.fromList(vertNrm), webgl.STATIC_DRAW);
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboTex);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, 
        new Float32List.fromList(vertTex), webgl.STATIC_DRAW);
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboBnP);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, 
        new Float32List.fromList(vertBnP), webgl.STATIC_DRAW);
    _gl.bindBuffer(webgl.ELEMENT_ARRAY_BUFFER, _ibo);
    _gl.bufferDataTyped(webgl.ELEMENT_ARRAY_BUFFER, 
        new Uint16List.fromList(indices), webgl.STATIC_DRAW);
    
    _nIndices = indices.length;
  }
}


var scene;
void main() {
  var canvas = document.querySelector("#glCanvas");
  scene = new TentacleScene(canvas);
  
  window.onClick.listen((event) => scene.render());

  window.animationFrame
    ..then((time) => animate(time));
}

void animate(double time) {
  scene.animate(time);
  scene.render();
  
  window.animationFrame
    ..then((time) => animate(time));
  
}
