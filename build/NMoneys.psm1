function Throw-If-Error
{
	[CmdletBinding()]
	param(
		[Parameter(Position=0,Mandatory=0)][string]$errorMessage = ('Error executing command {0}' -f $cmd)
	)
	if ($global:lastexitcode -ne 0) {
		throw ("Exec: " + $errorMessage)
	}
}

function Ensure-Release-Folders($base)
{
	(
		"$base\release\doc\net\", 
		"$base\release\doc\netstandard\", 
		"$base\release\lib\net40-client\", 
		"$base\release\lib\netstandard1.3\", 
		"$base\release\content\Infrastructure\Serialization\", 
		"$base\release\contentFiles\cs\any\Infrastructure\Serialization\"
	) |
		% { New-Item -Type directory $_ -Force | Out-Null }
}

function Build-Documentation($base, $configuration)
{
	imm-doc-net $base $configuration "NMoneys" -framework 'net'
	imm-doc-net $base $configuration "NMoneys.Exchange" -framework 'net'

	imm-doc-net $base $configuration "NMoneys" -framework 'netstandard' -target 'netstandard1.3'
	imm-doc-net $base $configuration "NMoneys.Exchange" -framework 'netstandard'  -target 'netstandard1.3'
}

function imm-doc-net($base, $configuration, $project, $target = '', $framework)
{
	$immDocNet_path = "$base\tools\ImmDoc.NET"
	$immDocNet = "$immDocNet_path\immDocNet.exe"
	$name = $project.Replace(".", "_")
	$artifact_path = Join-Path $base "src\$project\bin\$configuration"
	if ($target -ne '') {
		$artifact_path = Join-Path $artifact_path $target
	}
	$xml = Join-Path $artifact_path "$project.xml"
	$dll = Join-Path $artifact_path "$project.dll"
	
	& $immDocNet -vl:1 -fd "-pn:$project" `
		"-od:$base\release\doc\$framework\$name" `
		"-cn:$base\release\doc\$framework\$name.chm" `
		"-cp:$immDocNet_path" `
		$xml `
		$dll
	Throw-If-Error
}

function Copy-Artifacts($base, $configuration)
{
	copy-binaries $base $configuration
	copy-sources $base $configuration
	copy-doc $base $configuration
}

function copy-binaries($base, $configuration)
{
	$release_bin_dir = Join-Path $base release\lib\net40-client
	
	Copy-Item $base\src\NMoneys\bin\$configuration\NMoneys.dll $release_bin_dir
	Copy-Item $base\src\NMoneys\bin\$configuration\NMoneys.XML $release_bin_dir
	Copy-Item $base\src\NMoneys.Exchange\bin\$configuration\NMoneys.Exchange.dll $release_bin_dir
	Copy-Item $base\src\NMoneys.Exchange\bin\$configuration\NMoneys.Exchange.XML $release_bin_dir

	$release_bin_dir = Join-Path $base release\lib\netstandard1.3
	
	Copy-Item $base\src\NMoneys\bin\$configuration\netstandard1.3\NMoneys.dll $release_bin_dir
	Copy-Item $base\src\NMoneys\bin\$configuration\netstandard1.3\NMoneys.XML $release_bin_dir
	Copy-Item $base\src\NMoneys.Exchange\bin\$configuration\netstandard1.3\NMoneys.Exchange.dll $release_bin_dir
	Copy-Item $base\src\NMoneys.Exchange\bin\$configuration\netstandard1.3\NMoneys.Exchange.XML $release_bin_dir
}

function copy-doc($base){
	$release_bin_dir = Join-Path $base release\lib\net40-client
	$release_doc_dir = Join-Path $base release\doc\net
	
	Get-ChildItem $release_doc_dir -Filter *.chm |
		Copy-Item -Destination $release_bin_dir

	$release_bin_dir = Join-Path $base release\lib\netstandard1.3
	$release_doc_dir = Join-Path $base release\doc\netstandard
	
	Get-ChildItem $release_doc_dir -Filter *.chm |
		Copy-Item -Destination $release_bin_dir
}

function copy-sources()
{
	$src = Join-Path $base src\NMoneys.Serialization\
	$release_content_dir = Join-Path $base release\content\Infrastructure\Serialization
	
	$src_dirs = ("$src\Json_NET", "$src\Service_Stack", "$src\Mongo_DB", "$src\Entity_Framework", 
		(Join-Path $base "src\NMoneys.Serialization.Mongo_DB"))

	Get-ChildItem -Path $src_dirs -Filter "*.cs" |
		Copy-Item -Destination $release_content_dir

	$src_dirs = ("$src\Json_NET", (Join-Path $base "src\NMoneys.Serialization.Mongo_DB"))
	$release_contentFiles_dir = Join-Path $base release\contentFiles\cs\any\Infrastructure\Serialization
	Get-ChildItem -Path $src_dirs -Filter "*.cs" |
		Copy-Item -Destination $release_contentFiles_dir

	Get-ChildItem -Path "$src\Json_Net" -Filter "*.cs" |
		Get-Content |
		% {$_ -replace "Newtonsoft", "Raven.Imports.Newtonsoft"} | 
		% {$_ -replace ".Json_NET", ".Raven_DB"} |
		Set-Content ("$release_content_dir\Raven_DB.cs", "$release_contentFiles_dir\Raven_DB.cs")
}

function Generate-Packages($base)
{
	$nuget = Join-Path $base tools\nuget\nuget.exe
	$release_dir = Join-Path $base release

	Get-ChildItem -File -Filter '*.nuspec' -Path $base  | 
		% { 
			& $nuget pack $_.FullName -OutputDirectory $release_dir -BasePath $release_dir /verbosity quiet
			Throw-If-Error
		}
}

function Generate-Zip-Files($base)
{
	$version = get-version-from-package $base 'NMoneys'
		('NMoneys.dll', 'NMoneys.XML', 'NMoneys.chm') |
		% { 
			zip-bin $base $version 'NMoneys' $_ -framework 'net40-client' -abbreviation 'net' | Out-Null 
			zip-bin $base $version 'NMoneys' $_ -framework 'netstandard1.3' -abbreviation 'netstandard' | Out-Null 
		}

	$version = get-version-from-package $base 'NMoneys.Exchange'
	('NMoneys.Exchange.dll', 'NMoneys.Exchange.XML', 'NMoneys_Exchange.chm') |
		% { 
			zip-bin $base $version 'NMoneys.Exchange' $_ -framework 'net40-client' -abbreviation 'net'| Out-Null
			zip-bin $base $version 'NMoneys.Exchange' $_ -framework 'netstandard1.3' -abbreviation 'netstandard'| Out-Null
		}
}

function zip-bin($base, $version, $zipName, $fileName, $framework, $abbreviation)
{
	$zip_file = Join-Path $base "\release\$zipName.$version-bin_$abbreviation.zip"
	$to_add = Join-Path $base "\release\lib\$framework\$fileName"

	zip $zip_file $to_add
	
	return $zip_file
}

function zip($zip_file, $to_add)
{
	& "$base\tools\Info-Zip\zip.exe" -jq $zip_file $to_add
	Throw-If-Error "Cannot add '$to_add' to '$zip_file'"
	
	return $zip_file
}

function get-version-from-package($base, $packageFragment)
{
	$pkgVersion = Get-ChildItem -Path "$base\release\" -File "$packageFragment*.nupkg" |
		? { $_.Name -match "$packageFragment\.(\d(?:\.\d){2})" } |
		select -First 1 -Property @{ Name = "value"; Expression = {$matches[1]} }

	return $pkgVersion.value
}

function Find-Versioned-Folder($base, $beginning)
{
	$dir = Get-ChildItem (Join-Path $base *) -Directory | where {$_.Name.StartsWith($beginning, [System.StringComparison]::OrdinalIgnoreCase)}
    # get first directory
    return  $dir[0]
}

function Find-Test-Assemblies($base, $configuration)
{
	$nmoneys = get-test-assembly $base $configuration "NMoneys"
	$exchange = get-test-assembly $base $configuration "NMoneys.Exchange"
	$serialization = get-test-assembly $base $configuration "NMoneys.Serialization"
	$mongo_db = get-test-assembly $base $configuration "NMoneys.Serialization.Mongo_DB"

	return ($nmoneys, $exchange, $serialization, $mongo_db)
}

function get-test-assembly($base, $config, $name, $target = '')
{
	$assembly_name = "$base\src\$name.Tests\bin\$config\"
	$assembly_name = Join-Path $assembly_name $target
	$assembly_name = Join-Path $assembly_name "$name.Tests.dll"
	return $assembly_name
}

function Run-Core-Tests($base, $config)
{
	$nmoneys = get-test-assembly $base $config "NMoneys" -target 'netcoreapp1.0'
	$exchange = get-test-assembly $base $config "NMoneys.Exchange" -target 'netcoreapp1.0'

	$release = Resolve-Path $base\release

	dotnet $nmoneys --result:"$release\NMoneys.TestResult.core.xml" --noheader
	Throw-If-Error
	dotnet $exchange --result:"$release\NMoneys.Exchange.TestResult.core.xml" --noheader
	Throw-If-Error
}

function Restore-Packages($base)
{
	# restoring .core test projects, restores .netstandard projects as well
	Get-ChildItem -File -Recurse -Path "$base\src" -Include @('*Tests.core.csproj', '*.Tools.csproj') |
	ForEach-Object { dotnet restore $_.FullName }
}

export-modulemember -function Throw-If-Error, Ensure-Release-Folders, Build-Documentation, Copy-Artifacts, Generate-Packages, Generate-Zip-Files, Find-Versioned-Folder, Find-Test-Assemblies, Run-Core-Tests, Restore-Packages