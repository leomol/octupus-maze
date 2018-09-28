' firmware -- Lists all compatible COM ports to upgrade their firmware.
' 2015-12-05. Leonardo Molina.
' 2018-05-24. Last modified.

done = false
notFoundMessage = ""
do while not done
	done = true
	do
		set portList = GetComPorts()
		set optionsList = CreateObject("Scripting.Dictionary")
		portnames = portList.Keys
		optionsText = vbCR
		for each pname in portnames
			Set info = portList.item(pname)
			' Match ATmega2560.
			if InStr(1, info.PNPDeviceID, "USB\VID_2A03") Or InStr(1, info.PNPDeviceID, "USB\VID_2341") then
				optionsText = optionsText & "    *" & info.Name & vbCR
				optionsList.Add LCase(pname), 1
			end if
		next
		optionsList.Add "cancel", 1
		
		if (optionsList.Count < 2) then
			choice = MsgBox(notFoundMessage & "Would you like to update the firmware of your Arduino?" & vbCR & "Click ""Yes"" after connecting it to your computer or " & vbCR & "Click ""No"" to update this at a later time.",  vbYesNo, "Interphaser - Firmware upgrade")
			notFoundMessage = "No devices were detected. Make sure your device is connected and that Windows has installed its drivers." + vbCR + vbCR
			if choice = 6 then
				choice = ""
			else
				choice = "cancel"
			end if
		else
			choice = InputBox("Type in the COM id of a device listed below to replace its firmware (e.g. " & UCase(optionsList.Keys()(i)) & ")." & vbCR & "Click ""Cancel"" to update this at a later time." & vbCR & optionsText, "Interphaser - Firmware upgrade")
			if VarType(choice) = vbEmpty then
				choice = "cancel"
			else
				choice = LCase(choice)
			end if
		end if
	loop until optionsList.Exists(choice)

	if not StrComp(choice, "cancel", 1) = 0 then
		Set fso = CreateObject("Scripting.FileSystemObject")
		Set objFSO = CreateObject("Scripting.FileSystemObject")
		Set objFile = objFSO.GetFile(Wscript.ScriptFullName)
		ScriptDirectory = objFSO.GetParentFolderName(objFile)
		
		pushCmd = "avrdude.exe -C""avrdude.conf"" -v -patmega2560 -cwiring -P" & choice & " -b115200 -D -Uflash:w:""firmware.hex"":i"
		
		Set wshShell = CreateObject("WScript.Shell")
		Set oExec = wshShell.Exec(pushCmd)
		
		t = 1
		do while oExec.Status = 0
			WScript.Sleep 100
			if t = 10 then
				REM btn = wshShell.Popup("Please wait... ", 4, "Interphaser - Firmware upgrade", 0) 'Won't close in W8.
			end if
			t = t + 1
		loop
		
		
		if oExec.ExitCode = 0 then
			btn = msgbox("Firmware upgrade completed", 0, "Interphaser - Firmware upgrade")
		else
			btn = msgbox("Firmware upgrade not completed. Make sure other applications are not using the target COM port.", 5, "Interphaser - Firmware upgrade")
			if btn = 4 then
				done = false
			end if
		end if
	end if
loop
' Core idea for listing COM ports borrowed from
' http://collectns.blogspot.com/2011/11/vbscript-for-detecting-usb-serial-com.html
' http://github.com/todbot/usbSearch
'
function GetComPorts()
	set portList = CreateObject("Scripting.Dictionary")
	strComputer = "."
	set objWMIService = GetObject("winmgmts:\\" & strComputer & "\root\cimv2")
	set colItems = objWMIService.ExecQuery _
	("Select * from Win32_PnPEntity")
	for each objItem in colItems
		if not IsNull(objItem.Name) then
			set objRgx = CreateObject("VBScript.RegExp")
			objRgx.Global = true
			strDevName = objItem.Name
			objRgx.Pattern = "COM[0-9]+"
			set objRegMatches = objRgx.Execute(strDevName)
			
			if objRegMatches.Count = 1 then
				portList.Add objRegMatches.Item(0).Value, objItem
			end if
		end if
	next
	set GetComPorts = portList
end function