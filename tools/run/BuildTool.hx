import haxe.io.Path;
import sys.FileSystem;
#if neko
import neko.vm.Thread;
import neko.vm.Mutex;
import neko.vm.Tls;
import neko.vm.Tls;
#else
import cpp.vm.Thread;
import cpp.vm.Mutex;
import cpp.vm.Tls;
#end

class DirManager
{
   static var mMade = new Hash<Bool>();

   static public function make(inDir:String)
   {
      var parts = inDir.split("/");
      var total = "";
      for(part in parts)
      {
         if (part!="." && part!="")
         {
            if (total!="") total+="/";
            total += part;
            if (!mMade.exists(total))
            {
               mMade.set(total,true);
               if (!FileSystem.exists(total))
               {
                  try
                  {
                     #if haxe3
                     FileSystem.createDirectory(total + "/");
                     #else
                     FileSystem.createDirectory(total );
                     #end
                  } catch (e:Dynamic)
                  {
                     return false;
                  }
               }
            }
         }
      }
      return true;
   }
   public static function reset()
   {
      mMade = new Hash<Bool>();
   }
   static public function makeFileDir(inFile:String)
   {
      var parts = StringTools.replace (inFile, "\\", "/").split("/");
      if (parts.length<2)
         return;
      parts.pop();
      make(parts.join("/"));
   }

   static public function deleteFile(inName:String)
   {
      if (FileSystem.exists(inName))
      {
         BuildTool.log("rm " + inName);
         FileSystem.deleteFile(inName);
      }
   }

   static public function deleteExtension(inExt:String)
   {
      var contents = FileSystem.readDirectory(".");
      for(item in contents)
      {
         if (item.length > inExt.length && item.substr(item.length-inExt.length)==inExt)
            deleteFile(item);
      }
   }

   static public function deleteRecurse(inDir:String)
   {
      if (FileSystem.exists(inDir))
      {
         var contents = FileSystem.readDirectory(inDir);
         for(item in contents)
         {
            if (item!="." && item!="..")
            {
               var name = inDir + "/" + item;
               if (FileSystem.isDirectory(name))
                  deleteRecurse(name);
               else
               {
                  BuildTool.log("rm " + name);
                  FileSystem.deleteFile(name);
               }
            }
         }
         BuildTool.log("rmdir " + inDir);
         FileSystem.deleteDirectory(inDir);
      }
   }

}

class Compiler
{
   public var mFlags : Array<String>;
   public var mCFlags : Array<String>;
   public var mMMFlags : Array<String>;
   public var mCPPFlags : Array<String>;
   public var mOBJCFlags : Array<String>;
   public var mPCHFlags : Array<String>;
   public var mAddGCCIdentity: Bool;
   public var mExe:String;
   public var mOutFlag:String;
   public var mObjDir:String;
   public var mExt:String;

   public var mPCHExt:String;
   public var mPCHCreate:String;
   public var mPCHUse:String;
   public var mPCHFilename:String;
   public var mPCH:String;

   public var mGetCompilerVersion:String;
   public var mCompilerVersion:String;
   public var mCached:Bool;

   public var mID:String;

   public function new(inID,inExe:String,inGCCFileTypes:Bool)
   {
      mFlags = [];
      mCFlags = [];
      mCPPFlags = [];
      mOBJCFlags = [];
      mMMFlags = [];
      mPCHFlags = [];
      mAddGCCIdentity = inGCCFileTypes;
      mCompilerVersion = null;
      mObjDir = "obj";
      mOutFlag = "-o";
      mExe = inExe;
      mID = inID;
      mExt = ".o";
      mPCHExt = ".pch";
      mPCHCreate = "-Yc";
      mPCHUse = "-Yu";
      mPCHFilename = "/Fp";
      mCached = false;
   }

   function addIdentity(ext:String,ioArgs:Array<String>)
   {
      if (mAddGCCIdentity)
      {
         var identity = switch(ext)
           {
              case "c" : "c";
              case "m" : "objective-c";
              case "mm" : "objective-c++";
              case "cpp" : "c++";
              case "c++" : "c++";
              default:"";
         }
         if (identity!="")
         {
            ioArgs.push("-x");
            ioArgs.push(identity);
         }
      }
   }

   public function setPCH(inPCH:String)
   {
      mPCH = inPCH;
      if (mPCH=="gcc")
      {
          mPCHExt = ".h.gch";
          mPCHUse = "";
          mPCHFilename = "";
      }
   }

   public function needsPchObj()
   {
      return !mCached && mPCH!="gcc";
   }

   public function createCompilerVersion(inGroup:FileGroup)
   {
      if (mGetCompilerVersion!=null && mCompilerVersion==null)
      {
         var exe = mGetCompilerVersion;
         var args = new Array<String>();
         if (exe.indexOf (" ") > -1)
         {
            var splitExe = exe.split(" ");
            exe = splitExe.shift();
            args = splitExe.concat(args);
         }
 
         var versionString = Setup.readStderr(exe,args).join(" ");
         if (BuildTool.verbose)
         {
            BuildTool.println("--- Compiler verison ---" );
            BuildTool.println( versionString );
            BuildTool.println("------------------");
         }

         mCompilerVersion = haxe.crypto.Md5.encode(versionString);
         mCached = true;
      }

      return mCached;
   }

   public function precompile(inObjDir:String,inGroup:FileGroup)
   {
      var header = inGroup.mPrecompiledHeader;
      var file = inGroup.getPchName();

      var args = inGroup.mCompilerFlags.concat(mFlags).concat( mCPPFlags ).concat( mPCHFlags );

      var dir = inObjDir + "/" + inGroup.getPchDir() + "/";
      var pch_name = dir + file + mPCHExt;

      BuildTool.log("Make pch dir " + dir );
      DirManager.make(dir);

      if (mPCH!="gcc")
      {
         args.push( mPCHCreate + header + ".h" );

         // Create a temp file for including ...
         var tmp_cpp = dir + file + ".cpp";
         var outFile = sys.io.File.write(tmp_cpp,false);
         outFile.writeString("#include <" + header + ".h>\n");
         outFile.close();

         args.push( tmp_cpp );
         args.push(mPCHFilename + pch_name);
         args.push(mOutFlag + dir + file + mExt);
      }
      else
      {
         BuildTool.log("Make pch dir " + dir + header );
         DirManager.make(dir + header);
         args.push( "-o" );
         args.push(pch_name);
         args.push( inGroup.mPrecompiledHeaderDir + "/" + inGroup.mPrecompiledHeader + ".h" );
      }


      BuildTool.println("Creating " + pch_name + "...");
      var result = BuildTool.runCommand( mExe, args, true, false );
      if (result!=0)
      {
         if (FileSystem.exists(pch_name))
            FileSystem.deleteFile(pch_name);
         throw "Error creating pch: " + result + " - build cancelled";
      }
   }

   public function getObjName(inFile:File)
   {
      var path = new haxe.io.Path(inFile.mName);
      var dirId =
         haxe.crypto.Md5.encode(BuildTool.targetKey + path.dir).substr(0,8) + "_";

      return mObjDir + "/" + dirId + path.file + mExt;
   }

   public function compile(inFile:File,inTid:Int)
   {
      var path = new haxe.io.Path(mObjDir + "/" + inFile.mName);
      var obj_name = getObjName(inFile);

      var args = new Array<String>();
      
      args = args.concat(inFile.mCompilerFlags).concat(inFile.mGroup.mCompilerFlags).concat(mFlags);

      var ext = path.ext.toLowerCase();
      addIdentity(ext,args);

      var allowPch = false;
      if (ext=="c")
         args = args.concat(mCFlags);
      else if (ext=="m")
         args = args.concat(mOBJCFlags);
      else if (ext=="mm")
         args = args.concat(mMMFlags);
      else if (ext=="cpp" || ext=="c++")
      {
         allowPch = true;
         args = args.concat(mCPPFlags);
      }


      if (!mCached && inFile.mGroup.mPrecompiledHeader!="" && allowPch)
      {
         var pchDir = inFile.mGroup.getPchDir();
         if (mPCHUse!="")
         {
            args.push(mPCHUse + inFile.mGroup.mPrecompiledHeader + ".h");
            args.push(mPCHFilename + mObjDir + "/" + pchDir + "/" + inFile.mGroup.getPchName() + mPCHExt);
         }
         else
            args.unshift("-I"+mObjDir + "/" + pchDir);
      }


      var found = false;
      var cacheName:String = null;
      if (mCompilerVersion!=null)
      {
         var sourceName = inFile.mDir + inFile.mName;
         var contents = sys.io.File.getContent(sourceName);
         if (contents!="")
         {
            var md5 = haxe.crypto.Md5.encode(contents + args.join(" ") +
                inFile.mGroup.mDependHash + mCompilerVersion + inFile.mDependHash );
            cacheName = BuildTool.compileCache + "/" + md5;
            if (FileSystem.exists(cacheName))
            {
               sys.io.File.copy(cacheName, obj_name);
               BuildTool.println("use cache for " + obj_name + "(" + md5 + ")" );
               found = true;
            }
            else
            {
               BuildTool.log(" not in cache " + cacheName);
            }
         }
         else
            throw "Unkown source contents " + sourceName;
      }

      if (!found)
      {
         args.push( (new haxe.io.Path( inFile.mDir + inFile.mName)).toString() );

         var out = mOutFlag;
         if (out.substr(-1)==" ")
         {
            args.push(out.substr(0,out.length-1));
            out = "";
         }

         args.push(out + obj_name);
         var result = BuildTool.runCommand( mExe, args, true, inTid>=0 );
         if (result!=0)
         {
            if (FileSystem.exists(obj_name))
               FileSystem.deleteFile(obj_name);
            throw "Error : " + result + " - build cancelled";
         }
         if (cacheName!=null)
         {
           sys.io.File.copy(obj_name, cacheName );
           BuildTool.log(" caching " + cacheName);
         }
      }

      return obj_name;
   }
}


class Linker
{
   public var mExe:String;
   public var mFlags : Array<String>;
   public var mOutFlag:String;
   public var mExt:String;
   public var mNamePrefix:String;
   public var mLibDir:String;
   public var mRanLib:String;
   public var mFromFile:String;
   public var mLibs:Array<String>;
   public var mExpandArchives : Bool;
   public var mRecreate:Bool;

   public function new(inExe:String)
   {
      mFlags = [];
      mOutFlag = "-o";
      mExe = inExe;
      mNamePrefix = "";
      mLibDir = "";
      mRanLib = "";
      mExpandArchives = false;
      // Default to on...
      mFromFile = "@";
      mLibs = [];
      mRecreate = false;
   }
   public function link(inTarget:Target,inObjs:Array<String>,inCompiler:Compiler)
   {
      var ext = inTarget.mExt=="" ? mExt : inTarget.mExt;
      var file_name = mNamePrefix + inTarget.mOutput + ext;
      if(!DirManager.make(inTarget.mOutputDir))
      {
         throw "Unable to create output directory " + inTarget.mOutputDir;
      }
      var out_name = inTarget.mOutputDir + file_name;

      var libs = inTarget.mLibs.concat(mLibs);
      var v18Added = false;
      var isOutOfDateLibs = false;

      for(i in 0...libs.length)
      {
         var lib = libs[i];
         var parts = lib.split("{MSVC_VER}");
         if (parts.length==2)
         {
            var ver = "";
            if (BuildTool.isMsvc())
            {
               var current = parts[0] + "-" + BuildTool.getMsvcVer() + parts[1];
               if (FileSystem.exists(current))
               {
                  BuildTool.log("Using current compiler library " + current);
                  libs[i]=current;
               }
               else
               {
                  var v18 = parts[0] + "-18" + parts[1];
                  if (FileSystem.exists(v18))
                  {
                     BuildTool.log("Using msvc18 compatible library " + v18);
                     libs[i]=v18;
                     if (!v18Added)
                     {
                        v18Added=true;
                        libs.push( BuildTool.HXCPP + "/lib/Windows/libmsvccompat-18.lib");
                     }
                  }
                  else
                  {
                     throw "Could not find compatible library for " + lib + ", " + v18 + " does not exist";
                  }
               }
            }
            else
               libs[i] = parts[0] + parts[1];
         }
         if (!isOutOfDateLibs)
         {
            var lib = libs[i];
            if (FileSystem.exists(lib))
               isOutOfDateLibs = isOutOfDate(out_name,[lib]);
         }
      }


      if (isOutOfDateLibs || isOutOfDate(out_name,inObjs) || isOutOfDate(out_name,inTarget.mDepends))
      {
         var args = new Array<String>();
         var out = mOutFlag;
         if (out.substr(-1)==" ")
         {
            args.push(out.substr(0,out.length-1));
            out = "";
         }
         // Build in temp dir, and then move out so all the crap windows
         //  creates stays out of the way
         if (mLibDir!="")
         {
            DirManager.make(mLibDir);
            args.push(out + mLibDir + "/" + file_name);
         }
         else
         {
            if (mRecreate && FileSystem.exists(out_name))
            {
               BuildTool.println(" clean " + out_name );
               FileSystem.deleteFile(out_name);
            }
            args.push(out + out_name);
         }

         args = args.concat(mFlags).concat(inTarget.mFlags);


         var objs = inObjs.copy();

         if (mExpandArchives)
         {
            var isArchive = ~/\.a$/;
            var libArgs = new Array<String>();
            for(lib in libs)
            {
               if (isArchive.match(lib))
               {
                  var libName = Path.withoutDirectory(lib);
                  var libObjs = Setup.readStdout( mExe ,  ["t", lib] );
                  var objDir = inCompiler.mObjDir + "/" + libName;
                  DirManager.make(objDir);
                  var here = Sys.getCwd();
                  Sys.setCwd(objDir);
                  BuildTool.runCommand( mExe ,  ["x", lib], true, false );
                  Sys.setCwd(here);
                  for(obj in libObjs)
                     objs.push( objDir+"/"+obj );
               }
               else
                  libArgs.push(lib);
            }
            libs = libArgs;
         }


         // Place list of obj files in a file called "all_objs"
         if (mFromFile=="@")
         {
            var fname = inCompiler.mObjDir + "/all_objs";
            var fout = sys.io.File.write(fname,false);
            for(obj in objs)
               fout.writeString(obj + "\n");
            fout.close();
            args.push("@" + fname );
         }
         else
            args = args.concat(objs);

         args = args.concat(libs);

         var result = BuildTool.runCommand( mExe, args, true, false );
         if (result!=0)
            throw "Error : " + result + " - build cancelled";

         if (mRanLib!="")
         {
            args = [out_name];
            var result = BuildTool.runCommand( mRanLib, args, true, false );
            if (result!=0)
               throw "Error : " + result + " - build cancelled";
         }

         if (mLibDir!="")
         {
            sys.io.File.copy( mLibDir+"/"+file_name, out_name );
            FileSystem.deleteFile( mLibDir+"/"+file_name );
         }
         return  out_name;
      }

      return "";
   }
   function isOutOfDate(inName:String, inObjs:Array<String>)
   {
      if (!FileSystem.exists(inName))
         return true;
      var stamp = FileSystem.stat(inName).mtime.getTime();
      for(obj in inObjs)
      {
         if (!FileSystem.exists(obj))
            throw "Could not find " + obj + " required by " + inName;
         var obj_stamp =  FileSystem.stat(obj).mtime.getTime();
         if (obj_stamp > stamp)
            return true;
      }
      return false;
   }
}



class Stripper
{
   public var mExe:String;
   public var mFlags : Array<String>;

   public function new(inExe:String)
   {
      mFlags = [];
      mExe = inExe;
   }
   public function strip(inTarget:String)
   {
      var args = new Array<String>();

      args = args.concat(mFlags);

      args.push(inTarget);

      var result = BuildTool.runCommand( mExe, args, true,false );
      if (result!=0)
         throw "Error : " + result + " - build cancelled";
   }
}

class File
{
   public function new(inName:String, inGroup:FileGroup)
   {
      mName = inName;
      mDir = inGroup.mDir;
      if (mDir!="") mDir += "/";
      // Do not take copy - use reference so it can be updated
      mGroup = inGroup;
      mDepends = [];
      mCompilerFlags = [];
   }
   public function computeDependHash()
   {
      mDependHash = "";
      for(depend in mDepends)
         mDependHash += getFileHash(depend);
      mDependHash = haxe.crypto.Md5.encode(mDependHash);
   }

   public static function getFileHash(inName:String)
   {
      if (mFileHashes.exists(inName))
         return mFileHashes.get(inName);

      var content = sys.io.File.getContent(inName);
      var md5 = haxe.crypto.Md5.encode(content);
      mFileHashes.set(inName,md5);
      return md5;
   }

   public function isOutOfDate(inObj:String)
   {
      if (!FileSystem.exists(inObj))
         return true;
      var obj_stamp = FileSystem.stat(inObj).mtime.getTime();
      if (mGroup.isOutOfDate(obj_stamp))
         return true;

      var source_name = mDir+mName;
      if (!FileSystem.exists(source_name))
         throw "Could not find source '" + source_name + "'";
      var source_stamp = FileSystem.stat(source_name).mtime.getTime();
      if (obj_stamp < source_stamp)
         return true;
      for(depend in mDepends)
      {
         if (!FileSystem.exists(depend))
            throw "Could not find dependency '" + depend + "' for '" + mName + "'";
         if (FileSystem.stat(depend).mtime.getTime() > obj_stamp )
            return true;
      }
      return false;
   }
   static var mFileHashes = new Map<String,String>();
   public var mName:String;
   public var mDir:String;
   public var mDependHash:String;
   public var mDepends:Array<String>;
   public var mCompilerFlags:Array<String>;
   public var mGroup:FileGroup;
}


class HLSL
{
   var file:String;
   var profile:String;
   var target:String;
   var variable:String;

   public function new(inFile:String, inProfile:String, inVariable:String, inTarget:String)
   {
      file = inFile;
      profile = inProfile;
      variable = inVariable;
      target = inTarget;
   }

   public function build()
   {
	  if (!FileSystem.exists (Path.directory (target))) 
	  {
	     DirManager.make(Path.directory (target));
	  }
	  
      DirManager.makeFileDir(target);

      var srcStamp = FileSystem.stat(file).mtime.getTime();
      if ( !FileSystem.exists(target) || FileSystem.stat(target).mtime.getTime() < srcStamp)
      {
         var exe = "fxc.exe";
         var args =  [ "/nologo", "/T", profile, file, "/Vn", variable, "/Fh", target ];
         var result = BuildTool.runCommand(exe,args,BuildTool.verbose,false);
         if (result!=0)
         {
            throw "Error : Could not compile shader " + file + " - build cancelled";
         }
      }
   }
}



class FileGroup
{
   public function new(inDir:String,inId:String)
   {
      mNewest = 0;
      mFiles = [];
      mCompilerFlags = [];
      mPrecompiledHeader = "";
      mDepends = [];
      mMissingDepends = [];
      mOptions = [];
      mHLSLs = [];
      mDir = inDir;
      mId = inId;
   }

   public function preBuild()
   {
      for(hlsl in mHLSLs)
         hlsl.build();

      if (BuildTool.useCache)
      {
         mDependHash = "";
         for(depend in mDepends)
            mDependHash += File.getFileHash(depend);
         mDependHash = haxe.crypto.Md5.encode(mDependHash);
      }
   }

   public function addHLSL(inFile:String,inProfile:String,inVariable:String,inTarget:String)
   {
      addDepend(inFile);

      mHLSLs.push( new HLSL(inFile,inProfile,inVariable,inTarget) );
   }


   public function addDepend(inFile:String)
   {
      if (!FileSystem.exists(inFile))
      {
         mMissingDepends.push(inFile);
         return;
      }
      var stamp =  FileSystem.stat(inFile).mtime.getTime();
      if (stamp>mNewest)
         mNewest = stamp;

      mDepends.push(inFile);
   }


   public function addOptions(inFile:String)
   {
      mOptions.push(inFile);
   }

   public function getPchDir()
   {
      return "__pch/" + mId ;
   }

   public function checkOptions(inObjDir:String)
   {
      var changed = false;
      for(option in mOptions)
      {
         if (!FileSystem.exists(option))
         {
            mMissingDepends.push(option);
         }
         else
         {
            var contents = sys.io.File.getContent(option);

            var dest = inObjDir + "/" + haxe.io.Path.withoutDirectory(option);
            var skip = false;

            if (FileSystem.exists(dest))
            {
               var dest_content = sys.io.File.getContent(dest);
               if (dest_content==contents)
                  skip = true;
            }
            if (!skip)
            {
               DirManager.make(inObjDir);
               var stream = sys.io.File.write(dest,true);
               stream.writeString(contents);
               stream.close();
               changed = true;
            }
            addDepend(dest);
         }
      }
      return changed;
   }

   public function checkDependsExist()
   {
      if (mMissingDepends.length>0)
         throw "Could not find dependencies: " + mMissingDepends.join(",");
   }

   public function addCompilerFlag(inFlag:String)
   {
      mCompilerFlags.push(inFlag);
   }

   public function isOutOfDate(inStamp:Float)
   {
      return inStamp<mNewest;
   }

   public function setPrecompiled(inFile:String, inDir:String)
   {
      mPrecompiledHeader = inFile;
      mPrecompiledHeaderDir = inDir;
   }
   public function getPchName()
   {
      return Path.withoutDirectory(mPrecompiledHeader);
   }


   public var mNewest:Float;
   public var mCompilerFlags:Array<String>;
   public var mMissingDepends:Array<String>;
   public var mOptions:Array<String>;
   public var mPrecompiledHeader:String;
   public var mPrecompiledHeaderDir:String;
   public var mFiles: Array<File>;
   public var mHLSLs: Array<HLSL>;
   public var mDir : String;
   public var mId : String;
   public var mDepends:Array<String>;
   public var mDependHash : String;
}

#if haxe3
typedef Hash<T> = haxe.ds.StringMap<T>;
#end

typedef FileGroups = Hash<FileGroup>;

class Target
{
   public function new(inOutput:String, inTool:String,inToolID:String)
   {
      mOutput = inOutput;
      mOutputDir = "";
      mBuildDir = "";
      mToolID = inToolID;
      mTool = inTool;
      mFiles = [];
      mDepends = [];
      mLibs = [];
      mFlags = [];
      mExt = "";
      mSubTargets = [];
      mFileGroups = [];
      mFlags = [];
      mErrors=[];
      mDirs=[];
   }

   public function addFiles(inGroup:FileGroup)
   {
      mFiles = mFiles.concat(inGroup.mFiles);
      mFileGroups.push(inGroup);
   }
   public function addError(inError:String)
   {
      mErrors.push(inError);
   }
   public function checkError()
   {
       if (mErrors.length>0)
          throw mErrors.join("/");
   }
   public function clean()
   {
      for(dir in mDirs)
      {
         BuildTool.println("Remove " + dir + "...");
         DirManager.deleteRecurse(dir);
      }
   }

   public function getKey()
   {
      return mOutput + mExt;
   }

   public var mBuildDir:String;
   public var mOutput:String;
   public var mOutputDir:String;
   public var mTool:String;
   public var mToolID:String;
   public var mFiles:Array<File>;
   public var mFileGroups:Array<FileGroup>;
   public var mDepends:Array<String>;
   public var mSubTargets:Array<String>;
   public var mLibs:Array<String>;
   public var mFlags:Array<String>;
   public var mErrors:Array<String>;
   public var mDirs:Array<String>;
   public var mExt:String;
}

typedef Targets = Hash<Target>;
typedef Linkers = Hash<Linker>;

class BuildTool
{
   var mDefines : Hash<String>;
   var mIncludePath:Array<String>;
   var mCompiler : Compiler;
   var mStripper : Stripper;
   var mLinkers : Linkers;
   var mFileGroups : FileGroups;
   var mTargets : Targets;
   public static var sAllowNumProcs = true;
   public static var HXCPP = "";
   public static var verbose = false;
   public static var isWindows = false;
   public static var isLinux = false;
   public static var isMac = false;
   public static var useCache = false;
   public static var compileCache:String;
   public static var targetKey:String;
   public static var helperThread = new Tls<Thread>();
   public static var instance:BuildTool;
   static var printMutex:Mutex;


   public function new(inMakefile:String,inDefines:Hash<String>,inTargets:Array<String>,
        inIncludePath:Array<String> )
   {
      mDefines = inDefines;
      mFileGroups = new FileGroups();
      mCompiler = null;
      compileCache = "";
      mStripper = null;
      mTargets = new Targets();
      mLinkers = new Linkers();
      mIncludePath = inIncludePath;
      instance = this;
      var make_contents = "";
      try  {
         make_contents = sys.io.File.getContent(inMakefile);
      } catch (e:Dynamic) {
         println("Could not open build file '" + inMakefile + "'");
         Sys.exit(1);
      }

      if (!mDefines.exists("HXCPP_COMPILE_THREADS"))
         mDefines.set("HXCPP_COMPILE_THREADS", Std.string(getNumberOfProcesses()));

      var xml_slow = Xml.parse(make_contents);
      var xml = new haxe.xml.Fast(xml_slow.firstElement());
      
      parseXML(xml,"");

      if (mDefines.exists("HXCPP_COMPILE_CACHE"))
      {
         compileCache = mDefines.get("HXCPP_COMPILE_CACHE");
         // Don't get upset by trailing slash
         while(compileCache.length>1)
         {
            var l = compileCache.length;
            var last = compileCache.substr(l-1);
            if (last=="/" || last=="\\")
               compileCache = compileCache.substr(0,l-1);
            else
               break;
         }

         if (FileSystem.exists(compileCache) && FileSystem.isDirectory(compileCache))
         {
           useCache = true;
         }
         else
            throw "Could not find compiler cache: " + compileCache;

      }

      if (useCache && (!mDefines.exists("haxe_ver") && !mDefines.exists("HXCPP_DEPENDS_OK")))
      {
         if (verbose)
            println("ignoring cache because of possible missing dependencies");
         useCache = false;
      }

      if (useCache && verbose)
         println("Using cache " + compileCache );

      if (inTargets.remove("clear"))
         for(target in mTargets.keys())
            cleanTarget(target,false);

      if (inTargets.remove("clean"))
         for(target in mTargets.keys())
            cleanTarget(target,true);

      for(target in inTargets)
         buildTarget(target);
   }

   public static function isMsvc()
   {
      return instance.mDefines.get("toolchain")=="msvc";
   }
   static public function getMsvcVer()
   {
      return instance.mDefines.get("MSVC_VER");
   }

   inline public static function log(s:String)
   {
      if (verbose)
         Sys.println(s);
   }



   inline public static function println(s:String)
   {
      Sys.println(s);
   }


   function findIncludeFile(inBase:String) : String
   {
      if (inBase=="") return "";
     var c0 = inBase.substr(0,1);
     if (c0!="/" && c0!="\\")
     {
        var c1 = inBase.substr(1,1);
        if (c1!=":")
        {
           for(p in mIncludePath)
           {
              var name = p + "/" + inBase;
              if (FileSystem.exists(name))
                 return name;
           }
           return "";
        }
     }
     if (FileSystem.exists(inBase))
        return inBase;
      return "";
   }

   function parseXML(inXML:haxe.xml.Fast,inSection :String)
   {
      for(el in inXML.elements)
      {
         if (valid(el,inSection))
         {
            switch(el.name)
            {
                case "set" : 
                   var name = el.att.name;
                   var value = substitute(el.att.value);
                   mDefines.set(name,value);
                   if (name == "BLACKBERRY_NDK_ROOT")
                   {
                      Setup.setupBlackBerryNativeSDK(mDefines);
         		   }
                case "unset" : 
                   var name = el.att.name;
                   mDefines.remove(name);
                case "setup" : 
                   var name = substitute(el.att.name);
                   Setup.setup(name,mDefines);
                case "echo" : 
                   Sys.println(substitute(el.att.value));
                case "setenv" : 
                   var name = el.att.name;
                   var value = substitute(el.att.value);
                   mDefines.set(name,value);
                   Sys.putEnv(name,value);
                case "error" : 
                   var error = substitute(el.att.value);
                   throw(error);
                case "path" : 
                   var path = substitute(el.att.name);
                   if (verbose)
                      println("Adding path " + path );
                   var os = Sys.systemName();
                   var sep = mDefines.exists("windows_host") ? ";" : ":";
                   var add = path + sep + Sys.getEnv("PATH");
                   Sys.putEnv("PATH", add);
                    //trace(Sys.getEnv("PATH"));
                case "compiler" : 
                   mCompiler = createCompiler(el,mCompiler);

                case "stripper" : 
                   mStripper = createStripper(el,mStripper);

                case "linker" : 
                   if (mLinkers.exists(el.att.id))
                      createLinker(el,mLinkers.get(el.att.id));
                   else
                      mLinkers.set( el.att.id, createLinker(el,null) );

                case "files" : 
                   var name = el.att.id;
                   if (mFileGroups.exists(name))
                      createFileGroup(el, mFileGroups.get(name), name);
                   else
                      mFileGroups.set(name,createFileGroup(el,null,name));

                case "include" : 
                   var name = substitute(el.att.name);
                   var full_name = findIncludeFile(name);
                   if (full_name!="")
                   {
                      var make_contents = sys.io.File.getContent(full_name);
                      var xml_slow = Xml.parse(make_contents);
                      var section = el.has.section ? el.att.section : "";

                      parseXML(new haxe.xml.Fast(xml_slow.firstElement()),section);
                   }
                   else if (!el.has.noerror)
                   {
                      throw "Could not find include file " + name;
                   }
                case "target" : 
                   var name = substitute(el.att.id);
                   var overwrite = name=="default";
                   if (el.has.overwrite)
                      overwrite = true;
                   if (el.has.append)
                      overwrite = false;
                   if (mTargets.exists(name) && !overwrite)
                      createTarget(el,mTargets.get(name));
                   else
                      mTargets.set( name, createTarget(el,null) );
                case "section" : 
                   parseXML(el,"");
            }
         }
      }
   }
   
   
   public static function runCommand(exe:String, args:Array<String>,inPrint:Bool, inMultiThread:Bool ):Int
   {
      if (exe.indexOf (" ") > -1)
      {
         var splitExe = exe.split (" ");
         exe = splitExe.shift ();
         args = splitExe.concat (args);
      }

      var useSysCommand = !inMultiThread;
      
      if ( useSysCommand )
      {
         if (inPrint)
            println(exe + " " + args.join(" "));
         return Sys.command(exe,args);
      }
      else
      {
         var output = new Array<String>();
         if (inPrint)
            output.push(exe + " " + args.join(" "));
         var proc = new sys.io.Process(exe, args);
         var err = proc.stderr;
         var out = proc.stdout;
         var reader = BuildTool.helperThread.value;
         // Read stderr in separate hreead to avoid blocking ...
         if (reader==null)
         {
            var contoller = Thread.current();
            BuildTool.helperThread.value = reader = Thread.create(function()
            {
               while(true)
               {
                  var stream = Thread.readMessage(true);
                  var output:Array<String> = null;
                  try
                  {
                     while(true)
                     {
                        var line = stream.readLine();
                        if (output==null)
                           output = [ line ];
                        else
                           output.push(line);
                     }
                  }
                  catch(e:Dynamic){ }
                  contoller.sendMessage(output);
               }
            });
         }

         // Start up the error reader ...
         reader.sendMessage(err);

         try
         {
            while(true)
            {
               var line = out.readLine();
               output.push(line);
            }
         }
         catch(e:Dynamic){ }

         var errOut:Array<String> = Thread.readMessage(true);

         if (errOut!=null && errOut.length>0)
            output = output.concat(errOut);

         if (output.length>0)
         {
            if (printMutex!=null)
               printMutex.acquire();
            println(output.join("\n"));
            if (printMutex!=null)
               printMutex.release();
         }

         var code = proc.exitCode();
         proc.close();
         return code;
      }
   }

   public function cleanTarget(inTarget:String,allObj:Bool)
   {
      // Sys.println("Build : " + inTarget );
      if (!mTargets.exists(inTarget))
         throw "Could not find target '" + inTarget + "' to build.";
      if (mCompiler==null)
         throw "No compiler defined";

      var target = mTargets.get(inTarget);
      target.checkError();

      for(sub in target.mSubTargets)
         cleanTarget(sub,allObj);

      var restoreDir = "";
      if (target.mBuildDir!="")
      {
         restoreDir = Sys.getCwd();
         if (verbose)
            Sys.println("Enter " + target.mBuildDir);
         Sys.setCwd(target.mBuildDir);
      }

      DirManager.deleteRecurse(mCompiler.mObjDir);
      DirManager.deleteFile("all_objs");
      DirManager.deleteExtension(".pdb");
      if (allObj)
         DirManager.deleteRecurse("obj");

      if (restoreDir!="")
         Sys.setCwd(restoreDir);
   }
 



   public function buildTarget(inTarget:String)
   {
      // Sys.println("Build : " + inTarget );
      if (!mTargets.exists(inTarget))
         throw "Could not find target '" + inTarget + "' to build.";
      if (mCompiler==null)
         throw "No compiler defined";

      var target = mTargets.get(inTarget);
      target.checkError();

      for(sub in target.mSubTargets)
         buildTarget(sub);
 
      var threads = 1;

      // Old compiler can't use multi-threads because of pdb conflicts
      if (sAllowNumProcs)
      {
         var thread_var = mDefines.exists("HXCPP_COMPILE_THREADS") ?
            mDefines.get("HXCPP_COMPILE_THREADS") : Sys.getEnv("HXCPP_COMPILE_THREADS");

         if (thread_var==null)
            thread_var = getNumberOfProcesses();
         threads =  (thread_var==null || Std.parseInt(thread_var)<2) ? 1 :
            Std.parseInt(thread_var);
      }

      DirManager.reset();
      var restoreDir = "";
      if (target.mBuildDir!="")
      {
         restoreDir = Sys.getCwd();
         if (verbose)
            Sys.println("Enter " + target.mBuildDir);
         Sys.setCwd(target.mBuildDir);
      }

      targetKey = inTarget + target.getKey();
 
      var objs = new Array<String>();

      if (target.mFileGroups.length > 0)
         DirManager.make(mCompiler.mObjDir);
      for(group in target.mFileGroups)
      {
         group.checkOptions(mCompiler.mObjDir);

         group.checkDependsExist();

         group.preBuild();

         var to_be_compiled = new Array<File>();

         for(file in group.mFiles)
         {
            var obj_name = mCompiler.getObjName(file);
            objs.push(obj_name);
            if (file.isOutOfDate(obj_name))
            {
               if (useCache)
                  file.computeDependHash();
               to_be_compiled.push(file);
            }
         }

         var cached = useCache && mCompiler.createCompilerVersion(group);

         if (!cached && group.mPrecompiledHeader!="")
         {
            if (to_be_compiled.length>0)
               mCompiler.precompile(mCompiler.mObjDir, group);

            if (mCompiler.needsPchObj())
            {
               var pchDir = group.getPchDir();
               if (pchDir != "")
			   {
                  objs.push(mCompiler.mObjDir + "/" + pchDir + "/" + group.getPchName() + mCompiler.mExt);
			   }
            }
         }

         if (threads<2)
         {
            for(file in to_be_compiled)
               mCompiler.compile(file,-1);
         }
         else
         {
            var mutex = new Mutex();
            if (printMutex!=null)
               printMutex = new Mutex();
            var main_thread = Thread.current();
            var compiler = mCompiler;
            for(t in 0...threads)
            {
               Thread.create(function()
               {
                  try
                  {
                  while(true)
                  {
                     mutex.acquire();
                     if (to_be_compiled.length==0)
                     {
                        mutex.release();
                        break;
                     }
                     var file = to_be_compiled.shift();
                     mutex.release();

                     compiler.compile(file,t);
                  }
                  } catch (error:Dynamic)
                  {
                     main_thread.sendMessage("Error");
                  }
                  main_thread.sendMessage("Done");
               });
            }

            // Wait for theads to finish...
            for(t in 0...threads)
            {
              var result = Thread.readMessage(true);
              if (result=="Error")
                    throw "Error in building thread";
            }
         }
      }

      switch(target.mTool)
      {
         case "linker":
            if (!mLinkers.exists(target.mToolID))
               throw "Missing linker :\"" + target.mToolID + "\"";

            var exe = mLinkers.get(target.mToolID).link(target,objs, mCompiler);
            if (exe!="" && mStripper!=null)
               if (target.mToolID=="exe" || target.mToolID=="dll")
                  mStripper.strip(exe);
      }

      if (restoreDir!="")
         Sys.setCwd(restoreDir);
   }

   public function createCompiler(inXML:haxe.xml.Fast,inBase:Compiler) : Compiler
   {
      var c = inBase;
      if (inBase==null || inXML.has.replace)
      {
         c = new Compiler(inXML.att.id,inXML.att.exe,mDefines.exists("USE_GCC_FILETYPES"));
         if (mDefines.exists("USE_PRECOMPILED_HEADERS"))
            c.setPCH(mDefines.get("USE_PRECOMPILED_HEADERS"));
      }

      for(el in inXML.elements)
      {
         if (valid(el,""))
            switch(el.name)
            {
                case "flag" : c.mFlags.push(substitute(el.att.value));
                case "cflag" : c.mCFlags.push(substitute(el.att.value));
                case "cppflag" : c.mCPPFlags.push(substitute(el.att.value));
                case "objcflag" : c.mOBJCFlags.push(substitute(el.att.value));
                case "mmflag" : c.mMMFlags.push(substitute(el.att.value));
                case "pchflag" : c.mPCHFlags.push(substitute(el.att.value));
                case "objdir" : c.mObjDir = substitute((el.att.value));
                case "outflag" : c.mOutFlag = substitute((el.att.value));
                case "exe" : c.mExe = substitute((el.att.name));
                case "ext" : c.mExt = substitute((el.att.value));
                case "pch" : c.setPCH( substitute((el.att.value)) );
                case "getversion" : c.mGetCompilerVersion = substitute((el.att.value));
                case "section" :
                      createCompiler(el,c);
                case "include" :
                   var name = substitute(el.att.name);
                   var full_name = findIncludeFile(name);
                   if (full_name!="")
                   {
                      var make_contents = sys.io.File.getContent(full_name);
                      var xml_slow = Xml.parse(make_contents);
                      createCompiler(new haxe.xml.Fast(xml_slow.firstElement()),c);
                   }
                   else if (!el.has.noerror)
                   {
                      throw "Could not find include file " + name;
                   }
               default:
                   throw "Unknown compiler option: '" + el.name + "'";
         
 
            }
      }

      return c;
   }

   public function createStripper(inXML:haxe.xml.Fast,inBase:Stripper) : Stripper
   {
      var s = (inBase!=null && !inXML.has.replace) ? inBase :
                 new Stripper(inXML.att.exe);
      for(el in inXML.elements)
      {
         if (valid(el,""))
            switch(el.name)
            {
                case "flag" : s.mFlags.push(substitute(el.att.value));
                case "exe" : s.mExe = substitute((el.att.name));
            }
      }

      return s;
   }



   public function createLinker(inXML:haxe.xml.Fast,inBase:Linker) : Linker
   {
      var l = (inBase!=null && !inXML.has.replace) ? inBase : new Linker(inXML.att.exe);
      for(el in inXML.elements)
      {
         if (valid(el,""))
            switch(el.name)
            {
                case "flag" : l.mFlags.push(substitute(el.att.value));
                case "ext" : l.mExt = (substitute(el.att.value));
                case "outflag" : l.mOutFlag = (substitute(el.att.value));
                case "libdir" : l.mLibDir = (substitute(el.att.name));
                case "lib" : l.mLibs.push( substitute(el.att.name) );
                case "prefix" : l.mNamePrefix = substitute(el.att.value);
                case "ranlib" : l.mRanLib = (substitute(el.att.name));
                case "recreate" : l.mRecreate = (substitute(el.att.value)) != "";
                case "expandAr" : l.mExpandArchives = substitute(el.att.value) != "";
                case "fromfile" : l.mFromFile = (substitute(el.att.value));
                case "exe" : l.mExe = (substitute(el.att.name));
                case "section" : createLinker(el,l);
            }
      }

      return l;
   }

   public function createFileGroup(inXML:haxe.xml.Fast,inFiles:FileGroup,inName:String) : FileGroup
   {
      var dir = inXML.has.dir ? substitute(inXML.att.dir) : ".";
      var group = inFiles==null ? new FileGroup(dir,inName) : inFiles;
      for(el in inXML.elements)
      {
         if (valid(el,""))
            switch(el.name)
            {
                case "file" :
                   var file = new File(substitute(el.att.name),group);
                   for(f in el.elements)
                      if (valid(f,"") && f.name=="depend")
                         file.mDepends.push( substitute(f.att.name) );
                   group.mFiles.push( file );
                case "section" : createFileGroup(el,group,inName);
                case "depend" : group.addDepend( substitute(el.att.name) );
                case "hlsl" : group.addHLSL( substitute(el.att.name), substitute(el.att.profile),
                     substitute(el.att.variable), substitute(el.att.target)  );
                case "options" : group.addOptions( substitute(el.att.name) );
                case "compilerflag" : group.addCompilerFlag( substitute(el.att.value) );
                case "compilervalue" : group.addCompilerFlag( substitute(el.att.name) );
                                       group.addCompilerFlag( substitute(el.att.value) );
                case "precompiledheader" : group.setPrecompiled( substitute(el.att.name),
                          substitute(el.att.dir) );
            }
      }

      return group;
   }


   public function createTarget(inXML:haxe.xml.Fast,?inTarget:Target) : Target
   {
      var target:Target = inTarget;
      if (target==null)
      {
         var output = inXML.has.output ? substitute(inXML.att.output) : "";
         var tool = inXML.has.tool ? inXML.att.tool : "";
         var toolid = inXML.has.toolid ? substitute(inXML.att.toolid) : "";
         target = new Target(output,tool,toolid);
      }

      for(el in inXML.elements)
      {
         if (valid(el,""))
            switch(el.name)
            {
                case "target" : target.mSubTargets.push( substitute(el.att.id) );
                case "lib" : target.mLibs.push( substitute(el.att.name) );
                case "flag" : target.mFlags.push( substitute(el.att.value) );
                case "depend" : target.mDepends.push( substitute(el.att.name) );
                case "vflag" : target.mFlags.push( substitute(el.att.name) );
                               target.mFlags.push( substitute(el.att.value) );
                case "dir" : target.mDirs.push( substitute(el.att.name) );
                case "outdir" : target.mOutputDir = substitute(el.att.name)+"/";
                case "ext" : target.mExt = (substitute(el.att.value));
                case "builddir" : target.mBuildDir = substitute(el.att.name);
                case "files" : var id = el.att.id;
                   if (!mFileGroups.exists(id))
                      target.addError( "Could not find filegroup " + id ); 
                   else
                      target.addFiles( mFileGroups.get(id) );
                case "section" : createTarget(el,target);
            }
      }

      return target;
   }


   public function valid(inEl:haxe.xml.Fast,inSection:String) : Bool
   {
      if (inEl.x.get("if")!=null)
         if (!defined(inEl.x.get("if"))) return false;

      if (inEl.has.unless)
         if (defined(inEl.att.unless)) return false;

      if (inEl.has.ifExists)
         if (!FileSystem.exists( substitute(inEl.att.ifExists) )) return false;

      if (inSection!="")
      {
         if (inEl.name!="section")
            return false;
         if (!inEl.has.id)
            return false;
         if (inEl.att.id!=inSection)
            return false;
      }

      return true;
   }

   public function defined(inString:String) : Bool
   {
      return mDefines.exists(inString);
   }

   public static function getHaxelib(library:String):String
   {
      var proc = new sys.io.Process("haxelib",["path",library]);
      var result = "";
      try
      {
         while(true)
         {
            var line = proc.stdout.readLine();
            if (line.substr(0,1) != "-")
            {
               result = line;
               break;
            }
         }
      
      } catch (e:Dynamic) { };
      
      proc.close();
      
      if (result == "")
         throw ("Could not find haxelib path  " + library + " required by a source file.");
      
      return result;
   }
   
   // Setting HXCPP_COMPILE_THREADS to 2x number or cores can help with hyperthreading
   public static function getNumberOfProcesses():String
   {
      var env = Sys.getEnv("NUMBER_OF_PROCESSORS");
      if (env!=null)
         return env;

      var result = null;
      if (isLinux)
      {
         var proc = null;
         proc = new sys.io.Process("nproc",[]);
         try
         {
            result = proc.stdout.readLine();
            proc.close ();
         } catch (e:Dynamic) {}
      }
      else if (isMac)
      {
         var proc = new sys.io.Process("/usr/sbin/system_profiler", ["-detailLevel", "full", "SPHardwareDataType"]);	
         var cores = ~/Total Number of Cores: (\d+)/;
         try
         {
            while(true)
            {
               var line = proc.stdout.readLine();
               if (cores.match(line))
               {
                  result = cores.matched(1);
                  break;
               }
            }
         } catch (e:Dynamic) {}
         if (proc!=null)
            proc.close();
      }
      return result;
   }
   
   static var mVarMatch = new EReg("\\${(.*?)}","");
   public function substitute(str:String) : String
   {
      while( mVarMatch.match(str) )
      {
         var sub = mVarMatch.matched(1);
         if (sub.substr(0,8)=="haxelib:")
         {
            sub = getHaxelib(sub.substr(8));
         }
         else
            sub = mDefines.get(sub);

         if (sub==null) sub="";
         str = mVarMatch.matchedLeft() + sub + mVarMatch.matchedRight();
      }

      return str;
   }

   static function set64(outDefines:Hash<String>, in64:Bool)
   {
      if (in64)
      {
         outDefines.set("HXCPP_M64","1");
         outDefines.remove("HXCPP_32");
      }
      else
      {
         outDefines.set("HXCPP_M32","1");
         outDefines.remove("HXCPP_M64");
      }
   }
   
   
   // Process args and environment.
   static public function main()
   {
      var targets = new Array<String>();
      var defines = new Hash<String>();
      var include_path = new Array<String>();
      var makefile:String="";

      include_path.push(".");

      var args = Sys.args();
      var env = Sys.environment();

      verbose = env.exists("HXCPP_VERBOSE");

      // Check for calling from haxelib ...
      if (args.length>0)
      {
         var last:String = (new haxe.io.Path(args[args.length-1])).toString();
         var slash = last.substr(-1);
         if (slash=="/"|| slash=="\\") 
            last = last.substr(0,last.length-1);
         if (FileSystem.exists(last) && FileSystem.isDirectory(last))
         {
            // When called from haxelib, the last arg is the original directory, and
            //  the current direcory is the library directory.
            HXCPP = Sys.getCwd();
            defines.set("HXCPP",HXCPP);
            args.pop();
            Sys.setCwd(last);
         }
      }
      var os = Sys.systemName();
      isWindows = (new EReg("window","i")).match(os);
		if (isWindows)
		   defines.set("windows_host", "1");
      isMac = (new EReg("mac","i")).match(os);
		if (isMac)
		   defines.set("mac_host", "1");
      isLinux = (new EReg("linux","i")).match(os);
		if (isLinux)
		   defines.set("linux_host", "1");

      var isRPi = isLinux && Setup.isRaspberryPi();


      for(arg in args)
      {
         if (arg.substr(0,2)=="-D")
         {
            var val = arg.substr(2);
            var equals = val.indexOf("=");
            if (equals>0)
               defines.set(val.substr(0,equals), val.substr(equals+1) );
            else
               defines.set(val,"");
            if (val=="verbose")
               verbose = true;
         }
         else if (arg=="-v" || arg=="-verbose")
            verbose = true;
         else if (arg.substr(0,2)=="-I")
            include_path.push(arg.substr(2));
         else if (makefile.length==0)
            makefile = arg;
         else
            targets.push(arg);
      }

      Setup.initHXCPPConfig(defines);

      if (HXCPP=="" && env.exists("HXCPP"))
      {
         HXCPP = env.get("HXCPP") + "/";
         defines.set("HXCPP",HXCPP);
      }

      if (HXCPP=="")
      {
         if (!defines.exists("HXCPP"))
            throw "HXCPP not set, and not run from haxelib";
         HXCPP = defines.get("HXCPP") + "/";
         defines.set("HXCPP",HXCPP);
      }

      if (verbose)
         BuildTool.println("HXCPP : " + HXCPP);


      include_path.push(".");
      if (env.exists("HOME"))
        include_path.push(env.get("HOME"));
      if (env.exists("USERPROFILE"))
        include_path.push(env.get("USERPROFILE"));
      include_path.push(HXCPP + "/build-tool");

      var m64 = defines.exists("HXCPP_M64");
      var m32 = defines.exists("HXCPP_M32");
      if (m64==m32)
      {
         // Default to the current version of neko...
         var os = Sys.systemName();
         m64 = (~/64$/).match(os);
         m32 = !m64;
      }

      var msvc = false;
	  
	   if (defines.exists("ios"))
	   {
		  if (defines.exists("simulator"))
		  {
			 defines.set("iphonesim", "iphonesim");
		  }
		  else if (!defines.exists ("iphonesim"))
		  {
			 defines.set("iphoneos", "iphoneos");
		  }
	   }

      if (defines.exists("iphoneos"))
      {
		 defines.set("toolchain","iphoneos");
         defines.set("iphone","iphone");
         defines.set("apple","apple");
         defines.set("BINDIR","iPhone");
      }
      else if (defines.exists("iphonesim"))
      {
         defines.set("toolchain","iphonesim");
         defines.set("iphone","iphone");
         defines.set("apple","apple");
         defines.set("BINDIR","iPhone");
      }
      else if (defines.exists("android"))
      {
         defines.set("toolchain","android");
         defines.set("android","android");
         defines.set("BINDIR","Android");

         if (!defines.exists("ANDROID_HOST"))
         {
            if ( (new EReg("mac","i")).match(os) )
               defines.set("ANDROID_HOST","darwin-x86");
            else if ( (new EReg("window","i")).match(os) )
               defines.set("ANDROID_HOST","windows");
            else if ( (new EReg("linux","i")).match(os) )
               defines.set("ANDROID_HOST","linux-x86");
            else
               throw "Unknown android host:" + os;
         }
      }
      else if (defines.exists("webos"))
      {
         defines.set("toolchain","webos");
         defines.set("webos","webos");
         defines.set("BINDIR","webOS");
      }
      else if (defines.exists("tizen"))
      {
         if (defines.exists ("simulator"))
         {
            defines.set("toolchain","tizen-x86");
         }
         else
         {
            defines.set("toolchain","tizen");
         }
         defines.set("tizen","tizen");
         defines.set("BINDIR","Tizen");
      }
	  else if (defines.exists("blackberry"))
      {
		 if (defines.exists("simulator"))
		 {
			 defines.set("toolchain", "blackberry-x86");
		 }
		 else
		 {
		     defines.set("toolchain", "blackberry");
		 }
         defines.set("blackberry","blackberry");
         defines.set("BINDIR","BlackBerry");
      }
	  else if (defines.exists("emcc") || defines.exists("emscripten"))
	  {
         defines.set("toolchain","emscripten");
		 defines.set("emcc","emcc");
		 defines.set("emscripten","emscripten");
		 defines.set("BINDIR","Emscripten");
	  }
      else if (defines.exists("gph"))
      {
         defines.set("toolchain","gph");
         defines.set("gph","gph");
         defines.set("BINDIR","GPH");
      }
      else if (defines.exists("mingw") || env.exists("HXCPP_MINGW") )
      {
         set64(defines,m64);
         defines.set("toolchain","mingw");
         defines.set("mingw","mingw");
         defines.set("BINDIR",m64 ? "Windows64":"Windows");
      }
      else if (defines.exists("cygwin") || env.exists("HXCPP_CYGWIN"))
      {
         set64(defines,m64);
         defines.set("toolchain","cygwin");
         defines.set("cygwin","cygwin");
         defines.set("linux","linux");
         defines.set("BINDIR",m64 ? "Cygwin64":"Cygwin");
      }
      else if ( (new EReg("window","i")).match(os) )
      {
         defines.set("windows_host","1");
         // Cross-compile?
         if (defines.exists("rpi"))
         {
            defines.set("toolchain","linux");
            defines.set("xcompile","1");
            defines.set("linux","linux");
            defines.set("rpi","1");
            defines.set("hardfp","1");
            defines.set("BINDIR", "RPi");
         }
         else
         {
            set64(defines,m64);
            defines.set("toolchain","msvc");
            defines.set("windows","windows");
            msvc = true;
            if ( defines.exists("winrt") )
            {
               defines.set("BINDIR",m64 ? "WinRTx64":"WinRTx86");
            }
            else
            {
               defines.set("BINDIR",m64 ? "Windows64":"Windows");
            }
          }
      }
      else if ( isRPi )
      {
         defines.set("toolchain","linux");
         defines.set("linux","linux");
         defines.set("rpi","1");
         defines.set("hardfp","1");
         defines.set("BINDIR", "RPi");
      }
      else if ( (new EReg("linux","i")).match(os) )
      {
         set64(defines,m64);
         defines.set("toolchain","linux");
         defines.set("linux","linux");
         defines.set("BINDIR", m64 ? "Linux64":"Linux");
      }
      else if ( (new EReg("mac","i")).match(os) )
      {
         set64(defines,m64);
         // Cross-compile?
         if (defines.exists("linux"))
         {
            defines.set("mac_host","1");
            defines.set("linux","linux");
            defines.set("toolchain","linux");
            defines.set("xcompile","1");
            defines.set("BINDIR", m64 ? "Linux64":"Linux");
         }
         else
         {
            defines.set("toolchain","mac");
            defines.set("macos","macos");
            defines.set("apple","apple");
            defines.set("BINDIR",m64 ? "Mac64":"Mac");
         }
      }

      if (defines.exists("dll_import"))
      {
         var path = new haxe.io.Path(defines.get("dll_import"));
         if (!defines.exists("dll_import_include"))
            defines.set("dll_import_include", path.dir + "/include" );
         if (!defines.exists("dll_import_link"))
            defines.set("dll_import_link", defines.get("dll_import") );
      }


      if (defines.exists("apple") && !defines.exists("DEVELOPER_DIR"))
      {
          var proc = new sys.io.Process("xcode-select", ["--print-path"]);
          var developer_dir = proc.stdout.readLine();
          proc.close();
          if (developer_dir == "" || developer_dir.indexOf ("Run xcode-select") > -1)
          	 developer_dir = "/Applications/Xcode.app/Contents/Developer";
          if (developer_dir == "/Developer")
             defines.set("LEGACY_XCODE_LOCATION","1");
          defines.set("DEVELOPER_DIR",developer_dir);
      }

      if (defines.exists("iphone") && !defines.exists("IPHONE_VER"))
      {
         var dev_path = defines.get("DEVELOPER_DIR") + "/Platforms/iPhoneOS.platform/Developer/SDKs/";
         if (FileSystem.exists(dev_path))
         {
            var best="";
            var files = FileSystem.readDirectory(dev_path);
            var extract_version = ~/^iPhoneOS(.*).sdk$/;
            for(file in files)
            {
               if (extract_version.match(file))
               {
                  var ver = extract_version.matched(1);
                  if (Std.parseFloat (ver)>Std.parseFloat (best))
                     best = ver;
               }
            }
            if (best!="")
               defines.set("IPHONE_VER",best);
         }
      }
      
      if (defines.exists("macos") && !defines.exists("MACOSX_VER"))
      {
         var dev_path = defines.get("DEVELOPER_DIR") + "/Platforms/MacOSX.platform/Developer/SDKs/";
         if (FileSystem.exists(dev_path))
         {
            var best="";
            var files = FileSystem.readDirectory(dev_path);
            var extract_version = ~/^MacOSX(.*).sdk$/;
            for(file in files)
            {
               if (extract_version.match(file))
               {
                  var ver = extract_version.matched(1);
                  if (Std.parseFloat (ver)>Std.parseFloat (best))
                     best = ver;
               }
            }
            if (best!="")
               defines.set("MACOSX_VER",best);
         }
      }
      
      if (!FileSystem.exists(defines.get("DEVELOPER_DIR") + "/Platforms/MacOSX.platform/Developer/SDKs/"))
      {
         defines.set("LEGACY_MACOSX_SDK","1");
      }

      if (targets.length==0)
         targets.push("default");
   
      if (makefile=="")
      {
         Sys.println("Usage :  BuildTool makefile.xml [-DFLAG1] ...  [-DFLAGN] ... [target1]...[targetN]");
      }
      else
      {
         for(e in env.keys())
            defines.set(e, Sys.getEnv(e) );

         new BuildTool(makefile,defines,targets,include_path);
      }
   }
   
}
