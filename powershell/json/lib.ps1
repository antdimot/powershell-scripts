function Get-JsonFile {
    param (
        [Parameter(Mandatory)]
        [string]$FileName
    )

    try {
        $configFile = (Get-Content -Raw -Encoding UTF8 -path $fileName -ErrorAction Stop)

        return ($configFile | ConvertFrom-Json)
    }
    catch {
        Write-Error $_
        exit 1
    }
}

function Set-JsonFile {
    param (
        [Parameter(Mandatory)]
        [string]$FileName,
        [Parameter(Mandatory)]
        [object]$JsonObject
    )

    try {
        $json = $JsonObject | ConvertTo-Json

        Set-Content -Encoding UTF8 -Path $FileName -Value $json | Out-Null
    }
    catch {
        Write-Error $_
        exit 1
    }
}

function Get-Conditions {
    param (
        [Parameter(Mandatory)]
        [string]$Query
    )

    $result = @{}

    $tokens = $Query.Split(",")

    $tokens | ForEach-Object {
        $condition = $_.Split("=")

        $result.Add( $condition[0], $condition[1] )
    }

    return $result
}


function Get-PropertyValue {
    param (
        [Parameter(Mandatory)]
        [string]$PropertyName,
        [Parameter(Mandatory)]
        [string]$PropertyExpression
    )

    if( -not($PropertyExpression.Contains('[') ) ) {
        return $PropertyExpression
    }

    $expression = [regex]::Matches( $PropertyExpression, '\[[a-z0-9()\/=?.]*\]').Value

    if( $null -ne $expression -and $expression.StartsWith('[') ) {
        $expression = $expression.substring(1,$expression.Length-2)

        $metadata_type = [regex]::Matches( $expression, '[a-z0-9/?]*\(').Value
        $metadata_type = $metadata_type.substring(0,$metadata_type.Length-1)

        $metadata_query = [regex]::Matches( $expression, '\([a-z0-9,=?]*\)').Value
        $metadata_query =  $metadata_query.substring(1,$metadata_query.Length-2)

        $conditions = Get-Conditions -Query $metadata_query
        $keys = $conditions.Keys -as [string[]]
        $values = $conditions.Values -as [string[]]

        try {
            $metadata_file = Get-JsonFile -File "$metadata_type.json"

            $metadata_parameter = $metadata_file

            if( $keys.Count -eq 2 ) {
                $metadata_parameter = $metadata_file | Where-Object { 
                    $_.("$($keys[0])") -EQ "$($values[0])" -and
                    $_.("$($keys[1])") -EQ "$($values[1])"
                }
            }
            else {
                $metadata_parameter = $metadata_file | Where-Object { 
                    $_.("$($keys[0])") -EQ "$($values[0])"
                }
            }
            
            $metadata_property = [regex]::Matches( $expression, '\.[a-z.]*').Value
            $metadata_property = $metadata_property.substring(1,$metadata_property.Length-1)

            $metadata_value = $metadata_parameter.($metadata_property)

            return $metadata_value
        }
        catch {
            Write-Error $_
            exit 1
        }
    }
}

function Expand-JsonFile {
    param (
        [Parameter(Mandatory)]
        [string]$SourceFile,
        [string]$TargetFile = "out.json"
    )

    try {
        $json = Get-JsonFile -FileName $SourceFile

        $json | ForEach-Object {
            $item = $_

            $item.psobject.properties 
                | Where-Object { ($_.MemberType -eq "NoteProperty" `
                    -and $_.TypeNameOfValue -eq "System.String" `
                    -and $_.Value.StartsWith('[')
                ) }
                | ForEach-Object {
                    $property_value = Get-PropertyValue -PropertyName $_.name -PropertyExpression $_.value

                    $_.value = $property_value
                }
        }

        Set-JsonFile -FileName $TargetFile -JsonObject $json

        # return $json
    }
    catch {
        Write-Error $_
        exit 1
    }
}