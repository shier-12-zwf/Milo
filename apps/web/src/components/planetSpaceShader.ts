export const PLANET_VERTEX = `
attribute vec2 a_position;
void main(){gl_Position=vec4(a_position,0.,1.);}
`

// Analytic ray/sphere and ray/orbit intersections, not a rotating flat image.
export const PLANET_FRAGMENT = `
precision highp float;
uniform vec2 u_resolution;
uniform vec2 u_orbit;
uniform float u_time;
uniform float u_zoom;
uniform float u_warm;
uniform vec3 u_base;
uniform vec3 u_accent;
uniform sampler2D u_face;
float hash(vec3 p){p=fract(p*.3183099+vec3(.1,.2,.3));p*=17.;return fract(p.x*p.y*p.z*(p.x+p.y+p.z));}
float noise(vec3 p){vec3 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);}
float fbm(vec3 p){float f=0.,a=.5;for(int i=0;i<4;i++){f+=a*noise(p);p=p*2.03+vec3(3.2,1.7,4.1);a*=.5;}return f;}
mat3 ry(float a){float c=cos(a),s=sin(a);return mat3(c,0.,-s,0.,1.,0.,s,0.,c);}
mat3 rx(float a){float c=cos(a),s=sin(a);return mat3(1.,0.,0.,0.,c,s,0.,-s,c);}
void main(){
  vec2 uv=(gl_FragCoord.xy-.5*u_resolution)/u_resolution.y;
  vec3 ro=vec3(0.,.06,mix(4.5,3.35,u_zoom));
  vec3 rd=normalize(vec3(uv*2.25,-3.));
  float b=dot(ro,rd),c=dot(ro,ro)-1.;
  float disc=b*b-c;
  float t=disc>0.?-b-sqrt(disc):100.;
  vec3 col=vec3(0.);float alpha=0.;
  float closest=length(ro-rd*dot(ro,rd));
  // The atmosphere follows the spherical silhouette at every camera distance.
  float halo=exp(-max(closest-1.,0.)*13.)*.25;
  if(disc<0.){col=u_accent*halo;alpha=halo*.85;}
  mat3 turn=ry(-u_orbit.x)*rx(-u_orbit.y);
  vec3 ringNormal=normalize(vec3(.19,.81,.55));
  float denom=dot(rd,ringNormal);
  float rt=-dot(ro,ringNormal)/denom;
  vec3 rp=ro+rd*rt;
  float rr=length(rp);
  float ring=exp(-abs(rr-1.48)*190.)*.5+exp(-abs(rr-1.64)*260.)*.28;
  float angle=atan(rp.z,rp.x);
  ring*=.5+.5*smoothstep(-.7,.9,sin(angle*3.+u_time*.08));
  if(rt>0. && rt<t && abs(denom)>.01){col+=mix(u_accent,vec3(.94,.72,.5),.35)*ring;alpha=max(alpha,ring*.8);}
  if(disc>0.){
    vec3 p=ro+rd*t,n=normalize(p);
    vec3 local=turn*n;
    float clouds=fbm(local*5.+vec3(0.,u_time*.005,0.));
    float filaments=pow(1.-abs(sin(clouds*14.+local.y*3.)),9.);
    vec3 skyTint=mix(u_accent,vec3(.58,.64,.95),.22);
    vec3 surface=mix(u_base*.72,skyTint,clouds*.55+.27);
    surface+=skyTint*filaments*.17;
    vec3 light=normalize(vec3(-.65,.85,1.1));
    float diffuse=max(dot(n,light),0.);
    surface*=.4+diffuse*.78;
    // Tiny mineral-like lights are fixed on the surface and rotate with it.
    vec3 cell=local*145.;float spark=pow(hash(floor(cell)),52.);
    spark*=(1.-smoothstep(0.,.55,length(fract(cell)-.5)));
    surface+=vec3(.9,.87,1.)*spark*(1.1+diffuse);
    vec4 face=texture2D(u_face,vec2(local.x*.48+.5,local.y*.48+.5));
    float faceVisibility=smoothstep(.12,.4,local.z);
    surface=mix(surface,face.rgb*(.65+diffuse*.35),face.a*faceVisibility);
    float rim=pow(1.-max(dot(n,-rd),0.),3.);
    surface+=u_accent*rim*.85;
    float spec=pow(max(dot(reflect(-light,n),-rd),0.),40.);
    surface+=vec3(.85,.85,1.)*spec*.27;
    float homeGlow=pow(max(dot(local,normalize(vec3(.25,-.38,1.))),0.),20.);
    surface+=vec3(1.,.61,.28)*homeGlow*u_warm*.14;
    col=surface;alpha=1.;
    if(rt>0. && rt<t && abs(denom)>.01){col+=u_accent*ring*.55;}
  }
  // A quiet, warm companion light on its own spatial orbit.
  vec3 moon=vec3(cos(u_time*.08+.5)*1.55,sin(u_time*.08+.5)*.45,-.45);
  float mb=dot(ro-moon,rd),mc=dot(ro-moon,ro-moon)-.028*.028;
  float md=mb*mb-mc;
  if(md>0. && -mb-sqrt(md)<t){col=vec3(1.,.8,.56);alpha=1.;}
  float nearMoon=length((ro-moon)-rd*dot(ro-moon,rd));
  float moonGlow=exp(-nearMoon*55.)*.35;
  if(disc<0.){col+=vec3(1.,.65,.32)*moonGlow;alpha=max(alpha,moonGlow);}
  // Straight alpha: the canvas is composited over the star field.
  if(disc<0. && alpha>0.)col/=max(alpha,.001);
  gl_FragColor=vec4(col,alpha);
}
`
