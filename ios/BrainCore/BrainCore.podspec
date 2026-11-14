# Vendors the K-SLAS Rust core (native/brain_core) as brain_core.framework,
# which Flutter Rust Bridge opens at run time ("brain_core.framework/brain_core").
# Build it first with scripts/ios/build_brain_core.sh.
Pod::Spec.new do |s|
  s.name = 'BrainCore'
  s.version = '0.1.0'
  s.summary = 'K-SLAS Rust core for Flutter Rust Bridge.'
  s.homepage = 'https://github.com/Bkzazzau1/student_ui_demo'
  s.license = { :type => 'Proprietary', :text => 'Part of the K-SLAS app.' }
  s.author = 'K-SLAS'
  s.source = { :path => '.' }
  s.platform = :ios, '15.1'
  s.vendored_frameworks = 'brain_core.xcframework'
end
