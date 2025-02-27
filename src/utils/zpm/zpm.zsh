#!/usr/bin/env zsh

import ./zpm.zsh --as self
import ../../core/test_beta.zsh --as test
import ../global.zsh --as global
import ../color.zsh --as color
import ../log.zsh --as log
import ./create-dotfiles/create-dotfiles.zsh --as create_dotfiles
import ./create-package/create-package.zsh --as create_package
import ../bin.zsh --as bin

local jq;

function init() {
    jq=$( call bin.jq )
}

##
# print a message
# @param --message|-m <string> The error message
# @return <boolean>
##
function zpm_error() {
    local inputMsg=''
    local args=("$@")
    for (( i = 1; i <= $#; i++ )); do
        local arg="${args[$i]}"
        case "${arg}" in
            --message|-m)
                (( i++ ))
                inputMsg="${args[$i]}"
            ;;
        esac
    done
    if [[ -z "${inputMsg}" ]]; then
        throw --error-message "The flag: --message|-m was requird" --exit-code 1
    fi
    echo "\e[1;41m ERROR \e[0m ${inputMsg}" >&2
}

##
# create a zpm-package.json file
# @param --data|-d <json> like: {name: "init", args: [], flags: {}, description: "Create a zpm-package.json file"}
# @return <void>
##
function create_zpm_json() {
    local inputData=''
    local args=("$@")
    for (( i = 1; i <= $#; i++ )); do
        local arg="${args[$i]}"
        case "${arg}" in
            --data|-d)
                (( i++ ))
                inputData="${args[$i]}"
            ;;
        esac
    done

    # if the input data is empty, then exit
    if [[ -z "${inputData}" ]]; then
        throw --error-message "The flag: --data|-d was requird" --exit-code 1
    fi

    # if the zpm-package.json file exists, then exit
    if [[ -f "zpm-package.json" ]]; then
        throw --error-message "The zpm-package.json file already exists" --exit-code 1
    fi

    local packageName=$($jq -j "${inputData}" -q "args.0.value" -t get)

    local config=$(cat <<EOF
{
    "name": "${packageName}",
    "version": "1.0.0",
    "description": "A zpm package",
    "main": "lib/main.zsh",
    "scripts": {
        "start": "zpm run lib/main.zsh",
        "test": "echo \"Error: no test specified\" && exit 1"
    },
    "keywords": [],
    "author": "",
    "license": "ISC"
}
EOF
)
    local conf_file="zpm-package.json"
    echo "${config}" > ${conf_file}
    echo "${config}"
    echo "Create ${conf_file} success"
    # create lib/main.zsh file
    local libDir="lib"
    if [[ ! -d ${libDir} ]]; then
        mkdir -p ${libDir}
    fi
    cat > ${libDir}/main.zsh <<EOF
#!/usr/bin/env zpm
function() {
    echo "Hello world"
}
EOF

}

##
# exec a zsh script
# @param --file|-f <string> The file path
# @return <void>
##
function exec_zsh_script() {
    local inputFile=''
    local args=("$@")
    for (( i = 1; i <= $#; i++ )); do
        local arg="${args[$i]}"
        case "${arg}" in
            --file|-f)
                (( i++ ))
                inputFile="${args[$i]}"
            ;;
        esac
    done
    if [[ -z "${inputFile}" ]]; then
        throw --error-message "The flag: --file|-f was requird" --exit-code 1
    fi
    
    # check the file was zsh file
    local fileExt=$(echo "${inputFile}" | awk -F '.' '{print $NF}')
    if [[ "${fileExt}" != "zsh" ]]; then
        local firstLine=$( head -n 1 ${inputFile} )
        local allowInterprerList=(
            '#!/usr/bin/env zsh'
            '#!/bin/zsh'
            '#!/usr/bin/env zpm'
        )
        if [[ -z allowInterprerList[${firstLine}] ]]; then
            call self.zpm_error -m "The file: ${inputFile} is not a zsh file"
            return ${FALSE}
        fi
    fi

    import ${inputFile:A} --as zshScript
}

##
# run a script in zpm-package.json
# @param --data|-d <json> like: {name: "init", args: [], flags: {}, description: "Create a zpm-package.json file"}
# @return <void>
##
function run_script() {
    local inputData=''
    local args=("$@")
    for (( i = 1; i <= $#; i++ )); do
        local arg="${args[$i]}"
        case "${arg}" in
            --data|-d)
                (( i++ ))
                inputData="${args[$i]}"
            ;;
        esac
    done

    # if the input data is empty, then exit
    if [[ -z "${inputData}" ]]; then
        throw --error-message "The flag: --data|-d was requird" --exit-code 1
    fi

    # check if the workspace path was set in the flags, and then set the workspace path as the zpm workspace
    local hasWorkspace=$($jq -j "${inputData}" -q "flags.workspace" -t has)
    if [[ ${hasWorkspace} == "true" ]]; then
        local workspace=$($jq -j "${inputData}" -q "flags.workspace" -t get)
        if [[ -n "${workspace}" ]]; then
            ZPM_WORKSPACE=${workspace}
        fi
    fi

    local scriptName=$($jq -j "${inputData}" -q "args.0.value" -t get)
    if [[ -f ${scriptName} ]]; then
        call self.exec_zsh_script -f ${scriptName}
        return $?;
    else
        # check the script name was included dot
        local hasDot=$(echo "${scriptName}" | grep -e "\.\\?.*\.[a-zA-Z0-9]\\+$" )
        if [[ -n "${hasDot}" ]]; then
            call self.zpm_error -m "the script file: ${scriptName} was not found in \"$(pwd)\""
            return ${FALSE}
        fi
    fi
    # try to run the script in the zpm-package.json file
    # check if the script name was not exits and then print the error message
    local zpmjson="${ZPM_WORKSPACE}/zpm-package.json"
    # if the zpm-package.json file exists, then exit
    if [[ ! -f "${zpmjson}" ]]; then
        call self.zpm_error -m "No ${zpmjson} was found in \"$(pwd)\""
         return 1;
    fi
    local zpmjsonData=$(cat ${zpmjson})
    local hasScripName=$($jq -j "${zpmjsonData}" -q "scripts.${scriptName}" -t has)
    if [[ ${hasScripName} == "false" ]]; then
        if [[ -f ${scriptName} ]]; then
            call self.exec_zsh_script -f ${scriptName}

        else
            call self.zpm_error -m "No script name: ${scriptName} was found in ${zpmjson}"
            return ${FALSE}
        fi
    fi

    # run the script
    local cmdData=$($jq -j "${zpmjsonData}" -q "scripts.${scriptName}" -t get)
    eval " ${cmdData}"
}

##
# install a package
# @param --data|-d <json> like: {name: "init", args: [], flags: {}, description: "Create a zpm-package.json file"}
# @return <void>
##
function install_package() {
    local inputData=''
    local args=("$@")
    for (( i = 1; i <= $#; i++ )); do
        local arg="${args[$i]}"
        case "${arg}" in
            --data|-d)
                (( i++ ))
                inputData="${args[$i]}"
            ;;
        esac
    done

    # if the input data is empty, then exit
    if [[ -z "${inputData}" ]]; then
        throw --error-message "The flag: --data|-d was requird" --exit-code 1
    fi

    local totalArgs=$($jq -j "${inputData}" -q "args" -t size)
    # install all dependences
    if [[ ${totalArgs} -eq 0 ]]; then
        call self.install_all_dependence -d ${inputData}
        return $?
    fi

    # install a dependence
    local packageName=$($jq -j "${inputData}" -q "args.0.value" -t get)
    
    # check the git cmd was exists
    if [[ ! -x "$(command -v git)" ]]; then
        call self.zpm_error -m "The git command was required to install a package"
        return ${FALSE}
    fi

    local savePackageDir="${ZPM_DIR}/packages/${packageName}"
    if [[ ! -d ${savePackageDir} ]]; then
        mkdir -p ${savePackageDir}
    fi

    # download the package to the packages directory.
    local tmpSavePackageDir=$(mktemp -d)
    git clone https://${packageName} ${tmpSavePackageDir}
    cd ${tmpSavePackageDir}
    # get the lastest commit id and rename the directory with the commit id
    local commitId=$(git rev-parse HEAD)
    # move the package directory to the package saved directory
    local packageSaveDir="${savePackageDir}/${commitId}"
    if [[ ! -d ${packageSaveDir} ]]; then
        mv ${tmpSavePackageDir} ${savePackageDir}/${commitId}
    fi
    cd -
    # update the zpm-package.json file
    local editZpmJson5Dependencies="${ZPM_DIR}/src/qjs-tools/bin/edit-zpm-json-dependencies"
    local zpmjson="zpm-package.json"
    local newjsonData=$(
    ${editZpmJson5Dependencies} -f ${zpmjson} \
        -k "${packageName}" \
        -v "${commitId}" -a set )
    cat > ${zpmjson} <<EOF
${newjsonData}
EOF
    # install the other dependences under the package.
    call self.loop_install_package --name "${packageName}" --version "${commitId}" --prefix "${packageName}"
}

##
# uninstall a package
# @param --data|-d <json> like: {name: "uninstall", args: [], flags: {}, description: "Create a zpm-package.json file"}
# @return <void>
##
function uninstall_package() {
    local inputData=''
    local args=("$@")
    for (( i = 1; i <= $#; i++ )); do
        local arg="${args[$i]}"
        case "${arg}" in
            --data|-d)
                (( i++ ))
                inputData="${args[$i]}"
            ;;
        esac
    done

    # if the input data is empty, then exit
    if [[ -z "${inputData}" ]]; then
        throw --error-message "The flag: --data|-d was requird" --exit-code 1
    fi
    local packageName=$($jq -j "${inputData}" -q "args.0.value" -t get)
    
    # check if the package name was not empty.
    if [[ -z "${packageName}" ]]; then
        call self.zpm_error -m "The package name was required"
        return ${FALSE}
    fi

    # check the zpm-package.json was existed or not.
    local zpmjson="zpm-package.json"
    if [[ ! -f ${zpmjson} ]]; then
        call self.zpm_error -m "No ${zpmjson} was found in \"$(pwd)\""
        return ${FALSE}
    fi

    local zpmjsonData=$(cat ${zpmjson})
    # check if the package was installed.
    packageName=$(echo "${packageName}" | sed 's/\./\\./g')
    local hasPackage=$($jq -j "${zpmjsonData}" -q "dependencies.${packageName}" -t has)
    if [[ ${hasPackage} == "false" ]]; then
        packageName=$(echo "${packageName}" | sed 's/\\./\./g')
        call self.zpm_error -m "The package: ${packageName} was not installed"
        return ${FALSE}
    fi

    local jsonStr=$($jq -j "${zpmjsonData}" -q "dependencies.${packageName}" -t delete)
    cat > ${zpmjson} <<EOF
${jsonStr}
EOF
}

##
# @param --data|-d <json> like: {name: "test", args: ["<directory>|file path | empty"], flags: {}, description: "Test files"}
# @return <void>
##
function test() {
    local inputData=''
    local args=("$@")
    for (( i = 1; i <= $#; i++ )); do
        local arg="${args[$i]}"
        case "${arg}" in
            --data|-d)
                (( i++ ))
                inputData="${args[$i]}"
            ;;
        esac
    done
    # if the input data is empty, then exit
    if [[ -z "${inputData}" ]]; then
        throw --error-message "The flag: --data|-d was requird" --exit-code 1
    fi
    local isTestPath=${FALSE}
    local argsSize=$($jq -j "${inputData}" -q "args" -t size)
    local testPath='.'
    if [[ ${argsSize} -gt 0 ]]; then
        testPath=$($jq -j "${inputData}" -q "args.0.value" -t get)
        if [[ ! -d ${testPath} &&  ! -f ${testPath} ]]; then
            throw --error-message "The test path: ${testPath} was not found" --exit-code 1
            return $?;
        esle
            isTestPath=${TRUE}
        fi
    fi

    typeset -g TRUE=0
    typeset -g FALSE=1
    
    typeset -g TOTAL_TESTS=0
    typeset -g TOTAL_FAILED_TESTS=0
    typeset -g TOTAL_PASSED_TESTS=0
    
    typeset -g START_TIME=$(date +%s )
    typeset -g TOTAL_FILES=0
    
    typeset -g IS_CURRENT_TEST_OK=${FALSE}
    typeset -g CURRENT_TEST_FILE=''
    typeset -g CURRENT_TEST_NAME=''
    
    local testFiles=($( find ${testPath} -name '*.test.zsh' -type f ))

    # filter the test files with the testIgnore field in zpm-package.json.
    if [[ -d ${testPath} ]]; then
        local packageJson=$(cat zpm-package.json)
        local hasTestIgnoreField=$( $jq -j "${packageJson}" -q "testIgnore" -t has )
        if [[ ${hasTestIgnoreField} == 'true' ]]; then
            local testIgnoreListCount=$( $jq -j "${packageJson}" -q "testIgnore" -t size )
            local testIgnoreListIndex=0
            while [[ ${testIgnoreListIndex} -lt ${testIgnoreListCount} ]]; do
                local testIgnore=$( $jq -j "${packageJson}" -q "testIgnore.${testIgnoreListIndex}" -t get )
                testFiles=($(printf '%s\n' ${testFiles[@]} | grep -vE "${testIgnore}"))
                testIgnoreListIndex=$(( testIgnoreListIndex + 1 ))
            done
        fi
    fi

    for testFile in ${testFiles[@]}; do
        local relativeTestFile=${testFile#./}
        call color.reset
        call color.shape_bold
        echo "$(call color.print TEST) ${relativeTestFile}"
        # load the test file
        . ${testFile}

        call global.set "TOTAL_FILES" "$(( TOTAL_FILES + 1 ))"

        # loop the test functions
        call global.set "CURRENT_TEST_FILE" "${relativeTestFile}"
        local testFunctions=($(call test.extract_test_functions ${testFile}))
        local testFunc=''
            for testFunc in ${testFunctions[@]}; do
                # execute the test function
                call global.set "CURRENT_TEST_NAME" "${testFunc}"
                call global.set IS_CURRENT_TEST_OK "${TRUE}"
                ${testFunc}
                call test.print_current_test_result ${testFunc} ${IS_CURRENT_TEST_OK}
                # Collecting test data
                call global.set "TOTAL_TESTS" "$(( TOTAL_TESTS + 1 ))"
                if [[ ${IS_CURRENT_TEST_OK} -eq ${TRUE} ]]; then
                call global.set "TOTAL_PASSED_TESTS" "$(( TOTAL_PASSED_TESTS + 1 ))"
                else
                call global.set "TOTAL_FAILED_TESTS" "$(( TOTAL_FAILED_TESTS + 1 ))"
                fi
            done
    done

    call color.reset
    call color.light_red
    call color.shape_bold
    local COLOR_TOTAL_FAILED_TESTS=$(call color.print ${TOTAL_FAILED_TESTS})

    call color.reset
    call color.light_green
    call color.shape_bold
    local COLOR_TOTAL_PASSED_TESTS=$(call color.print ${TOTAL_PASSED_TESTS})

    call color.reset
    call color.shape_bold
    local COLOR_TOTAL_FILES=$(call color.print ${TOTAL_TESTS})
    
echo "
Tests:        ${COLOR_TOTAL_FAILED_TESTS} failed, ${COLOR_TOTAL_PASSED_TESTS} passed, ${COLOR_TOTAL_FILES} total
Time:         $(( $(date +%s) - ${START_TIME} )) s
Test files:   ${TOTAL_FILES} f
Ran all test files."

    if [[ ${TOTAL_FAILED_TESTS} -gt 0 ]]; then
        exit 1;
    fi
}

##
# install all dependences for the current project
# @param --data|-d <json> like: {name: "install", args: [], flags: {}, description: "Create a zpm-package.json file"}
# @return <boolean>
##
function install_all_dependence() {
    local inputData=''
    local args=("$@")
    for (( i = 1; i <= $#; i++ )); do
        local arg="${args[$i]}"
        case "${arg}" in
            --data|-d)
                (( i++ ))
                inputData="${args[$i]}"
            ;;
        esac
    done

    # if the input data is empty, then exit
    if [[ -z "${inputData}" ]]; then
        throw --error-message "The flag: --data|-d was requird" --exit-code 1
    fi

    # check the zpm-package.json file was existed or not.
    local zpmjson="zpm-package.json"
    if [[ ! -f ${zpmjson} ]]; then
        call self.zpm_error -m "No ${zpmjson} was found in \"$(pwd)\""
        return ${FALSE}
    fi

    # check if the dependencies field was existed or not.
    local zpmJsonData=$(cat ${zpmjson})
    local hasDependenceFiled=$( $jq -j "${zpmJsonData}" -q "dependencies" -t has )
    if [[ ${hasDependenceFiled} == 'false' ]]; then
        call self.zpm_error -m "No any dependence was found in ${zpmjson}"
        return ${TRUE}
    fi

    # get dependencies from the zpm-package.json file
    typeset -A dependencies=()
    local dependence=$( $jq -j "${zpmJsonData}" -q "dependencies" -t keys )
    local dependenceCount=$( $jq -j "${zpmJsonData}" -q "dependencies" -t size )
    local index=0;
    while [[ ${index} -lt ${dependenceCount} ]]; do
        local packageName=$( $jq -j "$dependence" -q "${index}" -t get )
        local query=dependencies.$( sed 's/\./\\./g' <<< ${packageName} )
        local version=$( $jq -j "$zpmJsonData" -q "$query" -t get )
        call self.loop_install_package --name "${packageName}" --version "${version}" --prefix "${packageName}"
        index=$(( index + 1 ))
    done
}

##
# loop install a package
# @param --name|-n <string> The package name
# @param --version|-v <string> The package version
# @param --prefix|-p <string> The prefix for debug log
# @return <void>
##
function loop_install_package() {
    local inputName=''
    local inputVersion=''
    local inputPrefix=''
    local args=("$@")
    for (( i = 1; i <= $#; i++ )); do
        local arg="${args[$i]}"
        case "${arg}" in
            --name|-n)
                (( i++ ))
                inputName="${args[$i]}"
            ;;
            --version|-v)
                (( i++ ))
                inputVersion="${args[$i]}"
            ;;
            --prefix|-p)
                (( i++ ))
                inputPrefix="${args[$i]}"
        esac
    done

    # if the input name is empty, then exit
    if [[ -z "${inputName}" ]]; then
        throw --error-message "The flag: --name|-n was requird" --exit-code 1
    fi

    # if the input version is empty, then exit
    if [[ -z "${inputVersion}" ]]; then
        throw --error-message "The flag: --version|-v was requird" --exit-code 1
    fi

    call log.debug "install package path: ${inputPrefix}"

    local saveDir="${ZPM_DIR}/packages/${inputName}/${inputVersion}"
    call log.info "Install ${inputName}@${inputVersion} ..."
    if [[ -d ${saveDir} ]]; then
        call log.info "The package: ${inputName}@${inputVersion} was installed"
    else
        # download the package to the packages directory.
        local tmpDir=$(mktemp -d)
        git clone https://${inputName} ${tmpDir}
        cd ${tmpDir}
        git reset --hard ${inputVersion}

        # If the template directory is empty, then throw error.
        if [[ -z "$(ls -A ${tmpDir})" ]]; then
            throw --error-message "The package: ${inputName}@${inputVersion} installed failed" --exit-code 1
        fi
        cd -
        
        [[ ! -d  ${saveDir} ]] && mkdir -p $( dirname ${saveDir} )
        mv ${tmpDir} ${saveDir}
    fi
    call log.success "Install ${inputName}@${inputVersion} success"

    # download the dependence of the package
    local zpmjson="${saveDir}/zpm-package.json"
    if [[ ! -f ${zpmjson} ]]; then
        return ${TRUE}
    fi
    local zpmJsonData=$(cat ${zpmjson})
    local hasDependencies=$( $jq -j "${zpmJsonData}" -q "dependencies" -t has )
    if [[ ${hasDependencies} == 'false' ]]; then
        return ${TRUE}
    fi
     
    local hasDependenciesField=$( $jq -j "${zpmJsonData}" -q "dependencies" -t has )
    [[ ${hasDependenciesField} == 'false' ]] && return ${TRUE}
    
    local size=$( $jq -j "${zpmJsonData}" -q "dependencies" -t size )
    if [[ $size -gt 0 ]]; then
        local packageIndex=0
        while [[ ${packageIndex} -lt ${size} ]]; do
            local packageNames=$( $jq -j "${zpmJsonData}" -q "dependencies" -t keys )
            local name=$( $jq -j "$packageNames" -q "${packageIndex}" -t get )
            local query="dependencies.$( echo ${name} | sed 's/\./\\./g' )"
            local version=$( $jq -j "${zpmJsonData}" -q "${query}" -t get )
            call self.loop_install_package --name ${name} --version ${version} --prefix "${inputPrefix}->${name}"
            packageIndex=$(( packageIndex + 1 ))
        done
    fi
}

##
# create a new zpm project.
# @param --data|-d <json> like: {name: "create", args: [], flags: {}, description: "Create a zpm-package.json file"}
# @return <boolean>
##
function create() {
    local inputData=''
    local args=("$@")
    for (( i = 1; i <= $#; i++ )); do
        local arg="${args[$i]}"
        case "${arg}" in
            --data|-d)
                (( i++ ))
                inputData="${args[$i]}"
            ;;
        esac
    done

    # if the input data is empty, then exit
    if [[ -z "${inputData}" ]]; then
        throw --error-message "The flag: --data|-d was requird" --exit-code 1
    fi

    local template=$( $jq -j "${inputData}" -q flags.template -t get )

    case ${template} in
        dotfiles)
            call create_dotfiles.create_dotfiles -d ${inputData}
        ;;
        package)
            call create_package.create_package -d ${inputData}
        ;;
        *)
            throw --error-message "The template: ${template} was not supported" --exit-code 1
        ;;
    esac
}