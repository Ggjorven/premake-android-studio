-- Android Studio Premake Module

-- Module interface
local m = {}

local p = premake
local project = p.project
local workspace = p.workspace
local config = p.config
local fileconfig = p.fileconfig
local tree = p.tree
local src_dirs = {}
    
-- remove this if you want to embed the module
dofile "_preload.lua"

-- Functions
function m.is_kotlin_project(prj)
    for cfg in project.eachconfig(prj) do
        for _,file in ipairs(cfg.files) do
            local ext = path.getextension(file)
            if ext == '.kt' then
                return true
            end
        end
    end
    return false
end

function m.contains_kotlin_project(wks)
    for prj in workspace.eachproject(wks) do
        if m.is_kotlin_project(prj) then
            return true
        end
    end
    return false
end

-- GGJORVEN: Ugly global workspace variable
globalWorkspace = nil

function m.generate_workspace(wks)
    -- GGJORVEN: Set the global workspace
    globalWorkspace = wks

    p.x('// workspace %s', wks.name)
    p.x('// auto-generated by premake-android-studio')
    p.push('buildscript {')
    p.push('repositories {')
    
    if next(wks.androidrepositories) ~= nil then
        for _, rep in ipairs(wks.androidrepositories) do
            p.w("%s", rep)
        end
    else
        p.w('mavenCentral()')
        p.w('google()')
    end

    p.pop('}') -- repositories
    p.push('dependencies {')
    
    if wks.gradleversion then
        p.x("classpath '%s'", wks.gradleversion)
    else
        p.w("classpath 'com.android.tools.build:gradle:8.5.2'")
    end  

    local needs_kotlin_plugin = wks.kotlinversion or m.contains_kotlin_project(wks)
    if needs_kotlin_plugin then
        local kotlinversion = wks.kotlinversion or '1.6.0'
        p.w("classpath 'org.jetbrains.kotlin:kotlin-gradle-plugin:%s'", kotlinversion)
    end

    if wks.androiddependenciesworkspace then
        for _, dep in ipairs(wks.androiddependenciesworkspace) do
            p.x("classpath '%s'", dep)
        end
    end

    p.pop('}') -- dependencies
    p.pop('}') -- build scripts
    
    p.push('allprojects {')
    p.push('repositories {')

    if next(wks.androidrepositories) ~= nil then
        for _, rep in ipairs(wks.androidrepositories) do
            p.w("%s", rep)
        end
    else
        p.w('mavenCentral()')
        p.w('google()')
    end

    -- lib dirs for .aar and .jar files
    dir_list = nil
    for prj in workspace.eachproject(wks) do
        if prj.archivedirs then
            for _, dir in ipairs(prj.archivedirs) do
                if dir_list == nil then
                    dir_list = ""
                else
                    dir_list = (dir_list .. ', ')
                end
                dir_list = (dir_list .. '"' .. dir .. '"')
            end
        end
    end
            
    if dir_list then
        p.push('flatDir {')
        p.x('dirs %s', dir_list)
        p.pop('}') -- flat dir
    end
    
    p.pop('}') -- repositories
    p.pop('}') -- all projects
end

function m.generate_workspace_settings(wks)
    p.x('// auto-generated by premake-android-studio')
    for prj in workspace.eachproject(wks) do
        p.x('include ":%s"', prj.name)
        p.x('project(":%s").projectDir = file("%s/%s")', prj.name, prj.location, prj.name)
    end
    -- insert asset packs
    if wks.assetpacks then
        for name, value in pairs(wks.assetpacks) do
            for _, item in ipairs(value) do
                p.x('include ":%s"', name)
            end
        end
    end 
end

function m.generate_gradle_properties(wks)
    -- gradle properties
    if wks.gradleproperties then
        for _, prop in ipairs(wks.gradleproperties) do
            p.w(prop)
        end
    end
end

-- generate a run configuration xml for the application
function m.generate_run_configuration(wks)
    p.x('<!-- auto-generated by premake-android-studio -->')
    p.x('<component name="ProjectRunConfigurationManager">')
    local config = '<configuration default="false" name="'
    config = config .. wks.runconfigmodule
    config = config .. '" type="AndroidRunConfigurationType" '
    config = config .. 'factoryName="Android App" '
    config = config .. 'activateToolWindowBeforeRun="false">'
    p.x(config)
    p.x('<module name="android.' .. wks.runconfigmodule .. '" />')
  
    if wks.runconfigoptions then
        for name, value in pairs(wks.runconfigoptions) do
            p.x('<option name="' .. value[1] .. '" value="' .. value[2] .. '" />')
        end
    end

    p.x('</configuration>')
    p.x('</component>')
end

-- asset packs
function m.generate_asset_pack(wks)
    if wks.assetpacks then
        for name, value in pairs(wks.assetpacks) do
            for _, item in ipairs(value) do
                p.x("poop")
            end
        end
    end 
end

function get_android_program_kind(premake_kind)
    local premake_to_android_kind =
    {
        ["WindowedApp"] = "com.android.application",
        ["ConsoleApp"] = "com.android.application",
        ["StaticLib"] = "com.android.library",
        ["SharedLib"] = "com.android.library",
    }
    return premake_to_android_kind[premake_kind]
end
    
function get_cmake_program_kind(premake_kind)
    local premake_to_cmake_kind =
    {
        -- native components of applications are shared libs
        ["WindowedApp"] = "SHARED",
        ["ConsoleApp"] = "SHARED",
        ["SharedLib"] = "SHARED",
        ["StaticLib"] = "STATIC"
    }
    return premake_to_cmake_kind[premake_kind]
end

function get_dir(file)
    return string.match(file, ".*/")
end

-- Extract version number from "com.android.tools.build:gradle:7.3.0"
local function parse_version(str)
    local version = string.match(str, "(%d+%.%d+%.%d+)")
    if not version then
        return nil  -- Version not found
    end

    local major, minor, patch = version:match("(%d+)%.(%d+)%.(%d+)")
    if not major or not minor or not patch then
        return nil  -- Invalid version format
    end

    return {
        major = tonumber(major),
        minor = tonumber(minor),
        patch = tonumber(patch)
    }
end


function m.generate_manifest(prj)
    -- look for a manifest in project files
    for cfg in project.eachconfig(prj) do       
        for _, file in ipairs(cfg.files) do
            if string.find(file, "AndroidManifest.xml") then
                -- copy contents of manifest and write with premake
                manifest = io.open(file, "r")
                xml = manifest:read("*a")
                manifest:close()
                p.w(xml)
                return
            end
        end
    end

    -- auto generate stub android manifest
    p.w('<?xml version="1.0" encoding="utf-8"?>')
    p.push('<manifest xmlns:android="http://schemas.android.com/apk/res/android"')
    -- Setting the namespace via the package attribute in the source AndroidManifest.xml is no longer supported.
    -- This behaviour was introduced in com.android.tools.build:gradle:7.3.0.
    if prj.gradleversion then
        local version = parse_version(prj.gradleversion)
        if version.major < 7 or (version.major == 7 and version.minor <= 2) then
            p.x('package="lib.%s"', prj.name)
        end
    end
    p.w('android:versionCode="1"')
    p.w('android:versionName="1.0" >')
    p.pop('<application/>')
    p.pop('</manifest>')
end

function m.generate_googleservices(prj)
    -- look for a google-services in project files
    for cfg in project.eachconfig(prj) do
        for _, file in ipairs(cfg.files) do
            if string.find(file, "google.services.json") then
                -- copy contents of google-services and write with premake
                json_file = io.open(file, "r")
                json_content = json_file:read("*a")
                json_file:close()
                p.w(json_content)
                return
            end
        end
    end
end
    
function m.add_sources(cfg, category, exts, excludes, strip)        
    -- get srcDirs because gradle experimental with jni does not support adding single files :(
    local dir_list = nil
    for _, file in ipairs(cfg.files) do
        skip = false
        for _, exclude in ipairs(excludes) do
            if string.find(file, exclude) then
                skip = true
                break
            end
        end
        if not skip then
            for _, ext in ipairs(exts) do
                file_ext = path.getextension(file)
                if file_ext == ext then
                    if (dir_list == nil) then dir_list = ""
                    else dir_list = (dir_list .. ', ') 
                    end
                    new_dir = get_dir(file)
                    if strip then
                        loc = string.find(new_dir, strip)
                        if (loc) then
                            new_dir = new_dir:sub(0, loc-1 + string.len(strip))
                        end
                    end
                    dir_list = (dir_list .. '"' .. new_dir .. '"')
                end
            end
        end
    end
            
    if dir_list then 
        p.x((category .. '.srcDirs += [%s]'), dir_list)
    end
end

function m.csv_string_from_table(tab)
    csv_list = nil
    if tab then
        for _, v in ipairs(tab) do
            if csv_list == nil then
                csv_list = ""
            else
                csv_list = (csv_list .. ", ")
            end
            csv_list = (csv_list .. '"' .. v .. '"')
        end
    end
    return csv_list
end
    
function m.generate_cmake_lists(prj)
    p.w('cmake_minimum_required (VERSION 3.10)')
    
    cmake_file_exts =
    {
        ".cpp",
        ".c",
        ".h",
        ".hpp"    
    }
    
    local project_deps = ""
    
    -- include cmake dependencies
    for _, dep in ipairs(project.getdependencies(prj)) do
        wks = prj.workspace
        for prj in workspace.eachproject(wks) do
            if prj.name == dep.name then
                cmakef = (prj.location .. "/" .. prj.name .. "/" .. "CMakeLists.txt")
                local f = io.open(cmakef,"r")
                if f ~= nil then 
                    io.close(f)
                    -- Guarantee that we aren't defining the project more than once
                    p.x('if(NOT TARGET %s)', prj.name)
                    p.x('include(%s)', cmakef)
                    p.x('endif()')
                    project_deps = (project_deps .. " " .. prj.name)
                end
            end 
        end
    end
    
    p.x('project (%s)', prj.name)
    
    cmake_kind = get_cmake_program_kind(prj.kind)
    for cfg in project.eachconfig(prj) do                
        -- somehow gradle wants lowecase debug / release but 
        -- still passes "Debug" and "Release" to cmake
        p.x('if(CMAKE_BUILD_TYPE STREQUAL "%s")', cfg.name)
        -- target                
        local file_list = ""
        for _, file in ipairs(cfg.files) do
            for _, ext in ipairs(cmake_file_exts) do
                if path.getextension(file) == ext then
                    file_list = (file_list .. " " .. file)
                end
            end
        end
        if file_list ~= "" then
            p.x('add_library(%s %s %s)', prj.name, cmake_kind, file_list)
        end
        
        -- include dirs
        local include_dirs = ""
        for _, dir in ipairs(cfg.includedirs) do
            include_dirs = (include_dirs .. " " .. dir)
        end
        if include_dirs ~= "" then
            p.x('target_include_directories(%s PUBLIC %s)', prj.name, include_dirs)
        end
        
        -- include dirs
        local include_dirs = ""
        for _, dir in ipairs(cfg.includedirs) do
            include_dirs = (include_dirs .. " " .. dir)
        end
        if include_dirs ~= "" then
            p.x('target_include_directories(%s PUBLIC %s)', prj.name, include_dirs)
        end

        -- toolset
        local toolset = p.tools[cfg.toolset or "gcc"]

        -- C flags
        local c_flags = toolset.getcflags(cfg)  
        if #c_flags > 0 then
            p.w('set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} %s")', table.concat(c_flags, " "))
        end
        
        -- C++ flags
        local cxx_flags = toolset.getcxxflags(cfg)
        if #cxx_flags > 0 then
            p.w('set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} %s")', table.concat(cxx_flags, " "))
        end
        
        -- custom buildoptions
        p.x('target_compile_options(%s PUBLIC %s)', prj.name, table.concat(cfg.buildoptions, " ") .. " -std=" .. string.lower(prj.cppdialect)) -- GGJORVEN: Default C++ version flag
        
        -- linker options
        local linker_options = ""
        if project_deps then
            linker_options = linker_options .. project_deps
        end
        local ld_flags = toolset.getldflags(cfg)
        if ld_flags then
            linker_options = linker_options .. " " .. table.concat(ld_flags, " ")
        end

        -- libdirs
        for _, libdir in ipairs(cfg.libdirs) do
            linker_options = linker_options .. " -L" .. libdir
        end

        local links = toolset.getlinks(cfg, "system", "fullpath")
        if links then
            linker_options = linker_options .. " " .. table.concat(links, " ")
        end
        if #linker_options > 0 then
            p.x('target_link_libraries(%s %s)', prj.name, linker_options)
        end
                
        -- defines
        local defines = ""
        for _, define in ipairs(cfg.defines) do
            defines = (defines .. " " .. define)
        end
        if defines ~= "" then
            p.x('target_compile_definitions(%s PUBLIC %s)', prj.name, defines)
        end
        
        -- injecting custom cmake code 
        if prj.androidcmake then
            for _, line in ipairs(prj.androidcmake) do
                p.x(line)
            end
        end

        p.w('endif()')
        
    end
end

function m.generate_project(prj)
    p.x('// auto-generated by premake-android-studio')
    p.x("apply plugin: '%s'", get_android_program_kind(prj.kind))

    -- android plugins
    if prj.androidplugins then
        for _, plugin in ipairs(prj.androidplugins) do
            p.x("apply plugin: '%s'", plugin)
        end
    end

    if m.is_kotlin_project(prj) then
        local has_kotlin_plugin_already = prj.androidplugins and table.contains(prj.androidplugins, 'org.jetbrains.kotlin.android')
        if not has_kotlin_plugin_already then
            p.w("apply plugin: 'org.jetbrains.kotlin.android'")
        end
    end

    p.push('android {')

    if prj.androidnamespace then
        p.x('namespace "%s"', prj.androidnamespace)
    else -- GGJORVEN: Add default namespace
        p.x('namespace "%s"', path.getname(globalWorkspace.location) .. "." .. prj.name .. ".main")
    end

    complete_signing_info = false
    if prj.androidkeyalias and 
       prj.androidkeystorefile and 
       prj.androidkeypassword and 
       prj.androidstorepassword then
       complete_signing_info = true
    end
        
    -- signing config for release builds
    if complete_signing_info then
        p.push('signingConfigs {')
        p.push('config { ')
        p.x("keyAlias '%s'", prj.androidkeyalias)
        p.x("keyPassword '%s'", prj.androidkeypassword)
        p.x("storePassword '%s'", prj.androidstorepassword)
        p.x("storeFile file('%s')", prj.androidkeystorefile)
        p.pop('}') -- config
        p.pop('}') -- signingConfigs
    end
    
    -- asset packs
    if prj.assetpackdependencies then
        local assetpackstring = ""
        for _, name in ipairs(prj.assetpackdependencies) do
            if assetpackstring ~= "" then
                assetpackstring = (assetpackstring .. ", ")
            end
            assetpackstring = (assetpackstring .. "':" .. name .. "'")
        end
        if assetpackstring ~= "" then
            p.push('assetPacks = [')
            p.w(assetpackstring)
            p.pop(']')
        end
    end

    -- sdk / ndk etc
    if prj.androidsdkversion == nil then
        prj.androidsdkversion = "34"
    end
    if prj.androidminsdkversion == nil then
        prj.androidminsdkversion = "34"
    end        
        
    p.x('compileSdkVersion %s', prj.androidsdkversion)
    
    if prj.androidndkpath ~= nil then
        p.x('ndkPath \"%s\"', prj.androidndkpath)
    end

    if prj.androidndkversion ~= nil then
        p.x('ndkVersion \"%s\"', prj.androidndkversion)
    else
        if prj.androidndkpath ~= nil then
            local _, _, ndk_version = string.find(prj.androidndkpath, "ndk/(.+)")
            if ndk_version ~= nil then
                p.x('ndkVersion \"%s\"', ndk_version)
            end
        end
    end
    
    p.push('defaultConfig {')
    if prj.androidappid then
        p.x('applicationId "%s"', prj.androidappid)
    end
    p.x('minSdkVersion %s', prj.androidminsdkversion)
    p.x('targetSdkVersion %s', prj.androidsdkversion)

    if prj.androidversioncode == nil then
        prj.androidversioncode = "1"
    end
    if prj.androidversionname == nil then
        prj.androidversionname = "1.0"
    end
    p.w('versionCode %s', prj.androidversioncode)
    p.w('versionName \"%s\"', prj.androidversionname)

    ----------------------------------------------
    -- GGJORVEN: Custom rule for static libs
    ----------------------------------------------
    if prj.kind == "StaticLib" then
        p.push('externalNativeBuild {')
        p.push('cmake {')
        p.w('targets "%s"', prj.name)  -- Using prj.name to dynamically use the project name "Lib"
        p.pop('}') -- Closes cmake block
        p.pop('}') -- Closes externalNativeBuild block
    end
    ----------------------------------------------
    
    if prj.androidtestrunner ~= nil then
        p.x('testInstrumentationRunner \"%s\"', prj.androidtestrunner)
    end
    
    if complete_signing_info then
        p.x('signingConfig signingConfigs.config')
    end
    
    p.pop('}') -- defaultConfig 
            
    -- abis
    -- GGJORVEN: Default abi's
    if #prj.androidabis < 0 then
        prj.androidabis = { 'armeabi', 'armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64' }
    end

    abi_list = m.csv_string_from_table(prj.androidabis)
    p.push('buildTypes {')
    for cfg in project.eachconfig(prj) do
        p.push(string.lower(cfg.name) .. ' {')
        -- todo:
        -- p.w('signingConfig signingConfigs.config')
        if abi_list then
            p.push('ndk {')
            p.x('abiFilters %s', abi_list)
            p.pop('}')
        end

        for _, setting in ipairs(cfg.androidbuildsettings) do
            p.x('%s', setting)
        end

        p.pop('}') -- cfg.name
    end
    p.pop('}') -- build types

    -- custom build commands
    if prj.prebuildcommands then
        p.push('preBuild {')
        for _, cmd in ipairs(prj.prebuildcommands) do
            p.push('exec {')
            p.x("commandLine %s", cmd)
            p.pop('}') -- exec
        end
        p.pop('}') -- preBuild
    end
        
    -- cmake
    p.push('externalNativeBuild {')
    p.push('cmake {')
    p.w('path "CMakeLists.txt"')
    p.pop('}') -- cmake
    p.pop('}') -- externalNativeBuild
    
    p.push('sourceSets {')
    
    -- assets
    asset_dirs = m.csv_string_from_table(prj.assetdirs)

    if asset_dirs then
        p.push('main {')
        p.x('assets.srcDirs += [%s]', asset_dirs)
                
        if prj.androidmanifest then
            p.x('manifest.srcFile "%s"', prj.androidmanifest)
        end
        
        p.pop('}')
    end
    
    -- java and resource files
    for cfg in project.eachconfig(prj) do
        p.push(string.lower(cfg.name) .. ' {')
        m.add_sources(cfg, 'java', {'.java', '.kt'}, {})
        m.add_sources(cfg, 'res', {'.png', '.xml'}, {"AndroidManifest.xml"}, "/res/")
        m.add_sources(cfg, 'androidTest.java', {'.java'}, {})
        p.pop('}') -- cfg.name
    end
    p.pop('}') -- sources
    
    -- lint options to avoid abort on error
    p.push('lintOptions {')
    p.w("abortOnError = false")
    p.pop('}')

    if prj.postbuildcommands then
        p.push('gradle.buildFinished {')
        for _, cmd in ipairs(prj.postbuildcommands) do
            p.push('exec {')
            p.x("commandLine %s", cmd)
            p.pop('}') -- exec
        end
        p.pop('}') -- gradle.buildFinished
    end
    
    -- applicationVariants
    if prj.apkoutputpath ~= nil then
        p.push('applicationVariants.all { variant ->')
        p.push('variant.outputs.all { output ->')
        p.x('outputFileName = new File("%s" + variant.buildType.name, project.name + ".apk")', prj.apkoutputpath)
        p.pop('}')
        p.pop('}')
    end

    -- libraryVariants
    if prj.aaroutputpath ~= nil then
        p.push('libraryVariants.all { variant ->')
        p.push('variant.outputs.all { output ->')
        p.x('outputFileName = new File("%s" + variant.buildType.name, project.name + ".aar")', prj.aaroutputpath)
        p.pop('}')
        p.pop('}')
    end

    p.pop('}') -- android
            
    -- project dependencies, java links, etc
    p.push('dependencies {')
    
    -- aar / jar links
    for cfg in project.eachconfig(prj) do
        for _, link in ipairs(config.getlinks(cfg, "system", "fullpath")) do
            ext = path.getextension(link)
            if ext == ".aar" or ext == ".jar" then
                p.x("implementation (name:'%s', ext:'%s')", path.getbasename(link), ext:sub(2, 4))
            end
        end
        break
    end
    
    -- android dependencies
    if prj.androiddependencies then
        for _, dep in ipairs(prj.androiddependencies) do
            if dep:find("^implementation ") then
                p.x("%s", dep)
            else
                p.x("implementation '%s'", dep)
            end
        end
    end
    
    -- project compile links
    for _, dep in ipairs(project.getdependencies(prj, "dependOnly")) do
        p.x("implementation project(':%s')", dep.name)
    end
    
    -- android in-project dependencies 
    if prj.androidprojectdependencies then
        for _, dep in ipairs(prj.androidprojectdependencies) do
            p.x("implementation project (':%s')", dep)
        end        
    end

    p.pop('}') -- dependencies

end

--print("Premake: loaded module android-studio")

-- Return module interface
p.modules.android_studio = m
return m
