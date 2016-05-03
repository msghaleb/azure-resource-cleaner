<# 
.SYNOPSIS 
    Azure Service Cleaner

.DESCRIPTION 
    The script is to make it easier for you to clean up your Azure resources, without using the Azure portal. 
    All you need to do is to run the script and choose the resources you need to remove and press ok.

.REQUIREMENTS 
    You need to have Azure Powershell installed on your computer. 
    https://azure.microsoft.com/en-us/documentation/articles/powershell-install-configure/

.NOTES 
    Author     : Mohamed Ghaleb - mohamed.ghaleb@siemens.com

.LINK 
    http://tfl09.blogspot.com 

.TODO
    It would be nice if we can add the following as input from the user:
       - The $Loopbreaker: where the user can input how many times should the Cleaner try to remove his/her resources (when skipping those with dependencies)
       - Add the possibility to STOP the resources and not only remove them.
       - Give the user a possible to choose between STOP/Remove.
       - Test this with more than one subscription (currently not tested)
#>


# Setting the error reporting to Silent, as some resources will report as error due to dependences, which we will try again later. 
$ErrorActionPreference = "SilentlyContinue"

# Defining a hashtable to collect all the resources choosen for removal.
$RmRetry = @{}

# Defining a variable to know if an error occurred.
$ErrorOccurred= 0


# Check if you are logged into your Azure Subscription or even have Azure Powershell installed
try
{
    Get-AzureRmResource | out-null 
}
catch
{
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
}

# Now we will take the Error Message and check what's going on to react. 
 
# If you have the Azure powershell installed but not login it yet it will get you to log in.
if ($ErrorMessage -like '*login*')
{
    Login-AzureRmAccount
}
elseif ($ErrorMessage -like '*credentials*')
{
    Login-AzureRmAccount
}

# If you don't have the Azure Powershell installed
elseif ($ErrorMessage -like '*not recognized as the name of a cmdlet*')
{
    write-host "It seems that you don't have the Azure powershell installed, please install it from here: https://azure.microsoft.com/en-us/documentation/articles/powershell-install-configure/"
    $ErrorOccurred = 1
}

# If all good but you are not connected to the internet but don't have free connection
elseif ($ErrorMessage -like '*Object reference not set to an instance of an object*')
{
    write-host "Are you sure you are connected to the Internet? If yes, may be your proxy doesn't like me?"
    $ErrorOccurred = 1
}

#If another error accurred
else
{
    write-host "An Error occurred, please fix the error and try again. Below is the Error message "
    write-host $ErrorMessage -ForegroundColor "Red"
    $ErrorOccurred = 1
}

# If Nothing major occurred we will go forward.
if ($ErrorOccurred -eq 0)
{
    # Now we will get all your resources, and give you an Out Grid to choose them (use CTRL) and then import them into a Hashtable.
    Get-AzureRmResource | Select-Object ResourceName,ResourceType,ResourceGroupName, ResourceId | Out-GridView -Title "Select VM Deployments to Remove" -PassThru | ForEach-Object {
  
       $RmRetry.Add($($_.ResourceId), $($_.ResourceName)) 

    }

    # If you choose nothing, the Hashtable will have nothin in it and thus we need not to do anything.
    if ($RmRetry.Count -gt 0)
    {
        # Let's saw you have choosed something, we will define a LoopBreaker variable to get the Azure Cleaner to try that amound of times, I put 9 to make it try 9 times more than the number of resources you have choosen.
        # The problem here is that some resources depend on others, so we will pick one resource randomly and then if we fail to remove it we will pick another one randomly.
        # The LoopBreaker is the number of consequent failure.
        $LoopBreaker = $RmRetry.Count + 9
        write-host "Azure Service Cleaner will start to remove your selected services. Please note this process may take time." -foregroundcolor "green"
        write-host " "
        
        # Do while loop to start removing the resources, the loop will keep running untill:
        # 1- Either the LoopBreaker is less than the number of resources you have choosen (9 failuers in a row)
        # 2- or if the Hashtable is empty, which means all resources are remove.
        Do {
          # Here we do the 1st check from both checks above.
          if ($RmRetry.Count -lt $LoopBreaker)
          {
             # Pick a resource randomly
             $RmRandom = $RmRetry.GetEnumerator() | Get-Random -Count 1

             # Put the resource name in a valiable.
             $RmName = $RmRandom.Value | Out-String
             
             # Try to remove the resource
             try
             { 
               Remove-AzureRmResource -ResourceId $RmRandom.Name -Force

               # If the resource was removed successfully, we will get the user to know the good news, remove it from our hashtable and increment the Loopbreaker
               write-output "removed $RmName successfully."
               $RmRetry.Remove($RmRandom.Name)
               $LoopBreaker = $LoopBreaker + 1
             }
             catch
             {
               # If we failed to remove the resource, we will decrement the Loopbreaker by one. 
               $LoopBreaker = $LoopBreaker - 1
             }
          }
          # If the Loopbreaker is now less than the number of items in our hashtable we will know ok, we have tried for 10 times no luck, so we will get the user to know what's going on
          # We will also display the resources which we can not remove and break the loop.
          else
          {
             write-host "It seems that the service(s) you are choosing do have dependences, please try to remove them in order e.g. the VM has to be removed before the NIC" -foregroundcolor "red"
             write-host " "
             write-host "Here is the list of resources I've failed to remove, you can try choosing different resources or try on using the Azure portal." -foregroundcolor "green"
             $RmRetry | Format-Table @{L=’Resource Name';E={$_.Value}}, @{L=’Resource ID';E={$_.Name}}
             break
          }
        } # End of 'Do'
        While ($RmRetry.Count -gt 0)

        # If the Hashtable is rempty we will tell the user that all resources are removed
        if ($RmRetry.Count -eq 0)
        {
           write-output "All resources are removed."
        }
    }
    # If the user choosed nothing, we will tell him that we knew it ;-)
    elseif ($RmRetry.Count -eq 0)
    {
       write-output "Hmm .. are you sure you have choosen anything to remove?"
    }
}