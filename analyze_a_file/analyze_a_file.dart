import 'dart:async';
import 'dart:io' as io;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/file_system.dart' hide File;
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/source/package_map_resolver.dart';
import 'package:analyzer/src/context/builder.dart';
import 'package:analyzer/src/dart/sdk/sdk.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/generated/source_io.dart';
import 'package:analyzer/src/source/source_resource.dart';

/// Analyzes a single [io.File].
Future<CompilationUnit> analyzeFile(io.File file) async {
  // Use a [ResourceProvider] to locate files for the analyzer.
  var resourceProvider = PhysicalResourceProvider.INSTANCE;

  // Resolve the path of the local Dart SDK, by first finding the path to the VM.
  var dartExecutable = new io.File(io.Platform.resolvedExecutable);

  // If your `resolvedExecutable` is /usr/local/dart/bin/dart,
  // then the SDK path is /usr/local/dart.
  var dartBinDir = dartExecutable.parent;

  // Relative to the Dart VM executable, it would be:
  // `..`
  var dartSdkDir = dartBinDir.parent;

  // A [DartSdk] represents the local Dart SDK.
  //
  // We need to use our `resourceProvider` to get an analyzer-friendly
  // pointer to the SDK home.
  var sdk = new FolderBasedDartSdk(
      resourceProvider, resourceProvider.getFolder(dartSdkDir.absolute.path));

  // We need a set of resolvers that the analyzer can use to resolve the locations
  // of libraries within our SDK.
  var resolvers = [
    // A `DartUriResolver` resolves Dart core libraries, i.e. `dart:async`.
    new DartUriResolver(sdk),

    // A `ResourceUriResolver` resolves `package:foo/foo.dart` URI's to locations within the system.
    // The `resourceProvider` is what actually does the `dart:io` interop, however.
    new ResourceUriResolver(resourceProvider)
  ];

  // However, we need to be able to resolve URI's like `package:foo/foo.dart`.
  // Use a `ContextBuilder` to help us build a context that does this for us.
  // For our purposes, we can leave the other two arguments null.
  var builder = new ContextBuilder(resourceProvider, null, null);

  // We have to determine the system package root; in other words, the Pub cache.
  String pubCachePath;

  if (io.Platform.isWindows) {
    var appDataDir = new io.Directory(io.Platform.environment['APPDATA']);
    pubCachePath = appDataDir.uri.resolve('Pub/Cache').toFilePath();
  } else {
    var homeDir = new io.Directory(io.Platform.environment['HOME']);
    pubCachePath = homeDir.uri.resolve('.pub-cache').toFilePath();
  }

  // We need to build a map of packages and folders.
  var packageMap = builder.convertPackagesToMap(builder.createPackageMap(pubCachePath));
  
  var packageResolver = new PackageMapUriResolver(resourceProvider, packageMap);
  resolvers.add(packageResolver);

  // A `SourceFactory` produces analyzer-compatible sources, which abstract over Dart files, with extra metadata.
  var sourceFactory = new SourceFactory(resolvers);

  // Finally, create an `AnalysisContext`. This is where all the static analysis magic happens.
  var analysisContext = AnalysisEngine.instance.createAnalysisContext();
  analysisContext.sourceFactory = sourceFactory;

  // Now, let's get a `Source` that represents our input file.
  var source = new FileSource(resourceProvider.getFile(file.absolute.path));

  // We create a `ChangeSet` that contains information about events that occurred within the analysis context.
  // Here, we notify the analyzer that we've loaded a new file.
  var changeSet = new ChangeSet()..addedSource(source);

  // Let the analyzer know.
  analysisContext.applyChanges(changeSet);

  // Let's get cracking, and finally parse/analyze our file.
  var libraryElement = analysisContext.computeLibraryElement(source);
  var compilationUnit = analysisContext.resolveCompilationUnit(source, libraryElement);

  // Yay!
  return compilationUnit;
}
