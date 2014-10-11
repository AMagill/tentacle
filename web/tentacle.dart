import 'dart:html';
import 'dart:web_gl' as webgl;
import 'dart:typed_data';
import 'dart:math';
import 'package:vector_math/vector_math.dart';
import 'package:vector_math/vector_math_lists.dart';
import 'shader.dart';

class TentacleScene {
  final int NBONES = 20;
  int _width, _height;
  webgl.RenderingContext _gl;
  Shader _objShader, _skelShader;
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

varying vec4 vColor;
varying vec3 vNormal;

void main() {
  const float off = 1.0 / float(NBONES);

  mat4  boneMat    = mat4(1.0);
  mat4 totalRotMat = mat4(1.0);
  for (int i = NBONES-1; i >= 0; i--) {
    float influence = clamp(aBonePos - float(i-1), 0.0, 1.0);
    float rx = uBone[i].x;// * influence;
    float ry = uBone[i].y;// * influence;

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
    rotMat *= influence;
    rotMat += mat4(1.0) * (1.0-influence);
    boneMat *= rotMat;
    totalRotMat *= rotMat;
    // Translate back to the proper place
    vec4 center = vec4(0.0, off*float(i), 0.0, 0.0);
    vec4 shift  = center - rotMat * center;
    boneMat *= mat4(
      1.0,0.0,0.0,0.0,
      0.0,1.0,0.0,0.0,
      0.0,0.0,1.0,0.0,
      shift.x,shift.y,shift.z,1.0);
  }

  gl_Position = uProjection * uModelView * boneMat * vec4(aPosition, 1.0);
  
  vNormal = (totalRotMat * vec4(aNormal,0.0)).xyz;
  vColor = vec4(vNormal * 0.5 + 0.5, 1.0);
  //vColor = vec4(aTexture, 0.0, 1.0);
}
    """;
    
    String fsObject = """
precision mediump int;
precision mediump float;

varying vec4 vColor;
varying vec3 vNormal;

void main() {
  //gl_FragColor = vColor;//vec4(0.0, 1.0, 0.0, 1.0);

  vec3 ambientColor = vec3(0.6, 1.0, 0.6);
  vec3 diffuseColor = vec3(0.6, 0.6, 1.0);
  vec3 diffuse2Color = vec3(1.0, 0.4, 0.4);
  float ambient = 0.15;
  float diffuse = max(dot(vNormal, vec3(0.0, 1.0, 0.0)), 0.0);
  float diffuse2 = max(dot(vNormal, vec3(-1.0, 0.0, 0.0)), 0.0);
  vec3 totalColor = (ambient * ambientColor) + 
                    (diffuse * diffuseColor) +
                    (diffuse2 * diffuse2Color); 
  gl_FragColor = vec4(totalColor, 1.0);
}
    """;
    
    _objShader = new Shader(_gl, vsObject, fsObject, 
        {'aPosition': 0, 'aNormal': 1, 'aTexture': 2, 'aBonePos': 3});

    String vsSkel = """
precision mediump int;
precision mediump float;

attribute vec3  aPosition;

uniform mat4 uProjection;
uniform mat4 uModelView;

void main() {
  gl_PointSize = 6.0;
  gl_Position = uProjection * uModelView * vec4(aPosition, 1.0);
}
    """;
    
    String fsSkel = """
precision mediump int;
precision mediump float;

void main() {
  gl_FragColor = vec4(0.0, 0.8, 0.0, 1.0);
}
    """;
    
    _skelShader = new Shader(_gl, vsSkel, fsSkel, {'aPosition': 0});

  }
  
  void animate(double time) {
    for (var tentacle in tentacles) {
      tentacle.animate2(time);
    }
    //tentacles[0]._segRot[2] = PI/2;
  }
  
  void render() {
    _gl.clear(webgl.COLOR_BUFFER_BIT);
    
    var mProjection = makeOrthographicMatrix(-1, 1, -0.1, 1.9, -2, 2);
    var mModelView  = new Matrix4.identity().scale(1.8);
    
    _objShader.use();
    _gl.uniformMatrix4fv(_objShader['uProjection'], false, mProjection.storage);
    _gl.uniformMatrix4fv(_objShader['uModelView'],  false, mModelView.storage);
    _skelShader.use();
    _gl.uniformMatrix4fv(_skelShader['uProjection'], false, mProjection.storage);
    _gl.uniformMatrix4fv(_skelShader['uModelView'],  false, mModelView.storage);    
    
    for (var tentacle in tentacles) {
      _objShader.use();
      _gl.uniform2fv(_objShader['uBone[0]'], tentacle._segRot.buffer);
      tentacle.bind();
      tentacle.drawBody();
      /*
      _skelShader.use();
      _gl.disable(webgl.DEPTH_TEST);
      tentacle.drawSkel();
      _gl.enable(webgl.DEPTH_TEST);
      */
    }
  }
    
}

class Tentacle {
  webgl.RenderingContext _gl;
  webgl.Buffer _vboPos, _vboNrm, _vboTex, _vboBnP, _ibo, _vboSkl;
  double _length;
  int _nBones;
  int _nIndices = 0;
  var _segVel, _segRot, _bonePos;
  SimplexNoise _simplex;
    
  Tentacle(this._gl, this._length, this._nBones) {
    _vboPos = _gl.createBuffer();
    _vboNrm = _gl.createBuffer();
    _vboTex = _gl.createBuffer();
    _vboBnP = _gl.createBuffer();
    _vboSkl = _gl.createBuffer();
    _ibo    = _gl.createBuffer();
    generateGeometry();
        
    _segRot = new Vector2List(_nBones);
    _bonePos = new Vector3List(_nBones+1);
    _simplex = new SimplexNoise();

    _boneVel = new Vector3List(_nBones);
    for (var i = 0; i < _nBones + 1; i++) {
      _bonePos[i] = new Vector3(0.0, i.toDouble() / _nBones, 0.0);
    }        
  }
  
  var _boneVel;
  void animate(double time) {
    const noiseFrequency   = 0.0001;
    const noiseConsistency = 10.0;
    const noiseForce       = 0.001;
    const springForce      = 0.1;
    final springLength     = 1.0 / _nBones;
    const floorForce       = 1.0;
    const dampingForce     = 0.5;
    const straightForce    = 0.05;
    
    for (var i = 1; i < _nBones; i++) {
      final stiffness      = (_nBones - i) / _nBones.toDouble();

      // Noisy force
      var noise = new Vector3(
          _simplex.noise3D(time * noiseFrequency, i / noiseConsistency, 0.0),
          _simplex.noise3D(0.0, time * noiseFrequency, i / noiseConsistency),
          _simplex.noise3D(i / noiseConsistency, 0.0, time * noiseFrequency));
      _boneVel[i] += noise * noiseForce;
      
      // Spring force to previous
      {
        var boneVec = _bonePos[i+1] - _bonePos[i];
        var boneLen = boneVec.length;
        boneVec *= (boneLen - springLength) / boneLen;
        _boneVel[i] -= boneVec * springForce;
      }
      
      // Spring force to next
      if (i != _nBones-1) {
        var boneVec = _bonePos[i+1] - _bonePos[i+2];
        var boneLen = boneVec.length;
        boneVec *= (boneLen - springLength) / boneLen;
        _boneVel[i] -= boneVec * springForce;
      }
      
      // Prefer to be straight
      /*
      var lastVec = _bonePos[i] - _bonePos[i-1];
      lastVec.normalize();
      lastVec /= _nBones.toDouble();
      var thisVec = _bonePos[i+1] - _bonePos[i];
      thisVec.normalize();
      thisVec /= _nBones.toDouble();
      var prefPos = _bonePos[i] + lastVec;
      var straightVec = prefPos - _bonePos[i+1];
      _boneVel[i] += straightVec * straightForce * ((_nBones - i) / _nBones.toDouble());
      */
      /*
      if (i != _nBones-1) {
        var prefPos = (_bonePos[i+2] + _bonePos[i]) / 2.0;
        var prefVec = prefPos - _bonePos[i+1];
        _boneVel[i] += prefVec * ((_nBones - i) / _nBones.toDouble()) * 0.5;
      }*/
      //_boneVel[i] -= new Vector3(_bonePos[i+1].x, 0.0, _bonePos[i+1].z) * 0.001;
      /*
      if (i != _nBones-1) {
        var lastVec = _bonePos[i+1] - _bonePos[i];
        lastVec.normalize();
        var thisVec = _bonePos[i+2] - _bonePos[i+1];
        thisVec.normalize();
        _boneVel[i] -= lastVec.cross(thisVec).cross(thisVec) * stiffness * straightForce;
      } */    

      // Don't go past the floor
      _boneVel[i] -= new Vector3(0.0, min(_bonePos[i+1].y, 0.0) * floorForce, 0.0);

      // Damping force
      _boneVel[i] *= dampingForce;
      
      _bonePos[i+1] += _boneVel[i];
    }    
    
    
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboSkl);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, _bonePos.buffer, webgl.DYNAMIC_DRAW);
  }

  void animate2(double time) {
    final speed = 1.6;
    final damp  = 0.4;
    
    void boneTransform(Matrix4 mat, Vector2 rot) {
      mat.rotateZ(-rot.x);
      mat.rotateX( rot.y);
      mat.translate(0.0, 1.0/_nBones, 0.0);
    }
    
    // Add organically noisy motion
    //var newSegRot = new Vector2List(_nBones);
    // Generate skeleton
    //var bonePos = new Vector3List(_nBones+1);
    var culmMat = new Matrix4.identity();
    for (var i = 0; i < _nBones; i++) {
      var fx = _simplex.noise2D(time / 10000, i / 10);
      var fy = _simplex.noise2D(i / 10, time / 10000);
      //var newSegRot = new Vector2(0.0,0.0);
      var newSegRot = _segRot[i].clone();
      newSegRot += new Vector2(fx, fy) * ((i+1) / _nBones) * speed;
      newSegRot *= damp;

      // Check for intersections
      bool intersects = false;
      var culmMat2 = culmMat.clone();
      // We have to work out the locations of the rest of the skeleton,
      // and see if this move produced any intersections.
/*      for (var j = i; j < _nBones; j++) {
        boneTransform(culmMat2, _segRot[j]);
        var pos = culmMat2.getTranslation();
        
        if (pos.x < -0.1) {// &&
            //pos.x < _bonePos[j+1].x) {
          intersects = true;
          break;
        }
/*
        // We only have to test against joints before the one in question,
        // since the bend could have only produced intersections between its
        // two sides.
        for (var k = 0; k < i-4; k++) {
          if (pos.distanceTo(bonePos[k]) < radiusAt(j/_nBones) + radiusAt(k/_nBones)) {
            intersects = true;
            break;
          }
        }
      
        if (intersects) break;*/
      }*/
      if (!intersects)
        _segRot[i] = newSegRot;
      
      boneTransform(culmMat, _segRot[i]);
      _bonePos[i+1] = culmMat.getTranslation();
    }
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboSkl);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, _bonePos.buffer, webgl.DYNAMIC_DRAW);
    
    
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
  
  void drawBody() {
    _gl.drawElements(webgl.TRIANGLES, _nIndices, webgl.UNSIGNED_SHORT, 0);
    //_gl.drawElements(webgl.LINE_STRIP, _nIndices, webgl.UNSIGNED_SHORT, 0);
  }
  
  void drawSkel() {
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboSkl);
    _gl.vertexAttribPointer(0, 3, webgl.FLOAT, false, 0, 0);
    
    _gl.enableVertexAttribArray(0);
    _gl.disableVertexAttribArray(1);
    _gl.disableVertexAttribArray(2);
    _gl.disableVertexAttribArray(3);

    _gl.drawArrays(webgl.LINE_STRIP, 0, _nBones+1);
    _gl.drawArrays(webgl.POINTS, 0, _nBones+1);
  }
  
  double radiusAt(double pt) {
    return 0.1 * sqrt(1.0-pt);
  }
  
  void generateGeometry() {
    final nLoops = 50;
    final nSides = 30;
    final nVerts = nLoops * nSides + 1;
    
    var iv = 0;
    var vertPos = new Vector3List(nVerts);
    var vertNrm = new Vector3List(nVerts);
    var vertTex = new Vector2List(nVerts);
    var vertBnP = new Float32List(nVerts);
    var indices = new List<int>();

    // Generate body
    final radsPerSide = 2.0*PI/nSides;
    for (var i = 0; i < nLoops; i++) {
      final bonePos = i / (nLoops-1) * (_nBones-1);
      final radius = radiusAt(i/nLoops);
      for (var j = 0; j < nSides; j++) {
        vertPos[iv] = new Vector3(
            radius*sin(j*radsPerSide),   i / (nLoops-1),
            radius*cos(j*radsPerSide));
        vertBnP[iv] = bonePos.clamp(0.0, _nBones-1.0);
        final ny = 0.1/sqrt((nLoops-i)/nLoops);
        final nr = 1.0-ny*ny;
        vertNrm[iv] = new Vector3(
            nr*sin(j*radsPerSide),    ny,
            nr*cos(j*radsPerSide));
        vertTex[iv] = new Vector2(j / (nSides-1), i / (nLoops-1));
        iv++;
        
        if (i != 0) {
          final tl = iv - 1;
          final tr = (nSides-j > 1) ? iv : (iv-nSides);
          final bl = tl - nSides, br = tr - nSides; 
          indices.addAll([bl, br, tl,    br, tr, tl]);
        }
      }
    }
    // Add geometry for a tip converging to a point
    vertPos[iv] = new Vector3(0.0, 1.0 + 0.3/nLoops, 0.0);
    vertBnP[iv] = _nBones.toDouble();
    vertNrm[iv] = new Vector3(0.0, 1.0, 0.0);
    vertTex[iv] = new Vector2(0.5, 1.0);
    iv++;
    
    final t = iv - 1;
    for (var j = 0; j < nSides; j++) {
      final l = t - nSides + j;
      final r = (nSides-j > 1) ? (l+1) : (l+1-nSides);
      indices.addAll([l, r, t]);
    }

    // Buffer geometry
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboPos);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, vertPos.buffer, webgl.STATIC_DRAW);
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboNrm);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, vertNrm.buffer, webgl.STATIC_DRAW);
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboTex);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, vertTex.buffer, webgl.STATIC_DRAW);
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboBnP);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, vertBnP, webgl.STATIC_DRAW);
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
  
  window.animationFrame
    ..then((time) => animate(time));
}

void animate(double time) {
  scene.animate(time);
  scene.render();
  
  window.animationFrame
    ..then((time) => animate(time));
  
}
