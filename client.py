from PyQt5 import QtCore, QtGui, QtWidgets
import requests
import win32clipboard

class Login(QtWidgets.QDialog):
    def __init__(self, parent=None):
        super(Login, self).__init__(parent)
        self.textName = QtWidgets.QLineEdit(self)
        self.textPass = QtWidgets.QLineEdit(self)
        self.buttonLogin = QtWidgets.QPushButton('Login', self)
        self.buttonLogin.clicked.connect(self.handleLogin)
        layout = QtWidgets.QVBoxLayout(self)
        layout.addWidget(self.textName)
        layout.addWidget(self.textPass)
        layout.addWidget(self.buttonLogin)

    def handleLogin(self):
        global username
        global password
        username = self.textName.text()
        password = self.textPass.text()

        url = "https://wg.spoor.nu/login.php?user=" + username + "&pass=" + password
        r = requests.get(url)
        response = r.content.decode()
        print(response)
        
        if (response != "Fail!"):
            self.accept()
        else:
            QtWidgets.QMessageBox.warning(
                self, 'Error', 'Bad user or password')

class New(QtWidgets.QDialog):
    def __init__(self, parent=None):
        super(New, self).__init__(parent)
        self.devName = QtWidgets.QLineEdit(self)
        self.datePicker = QtWidgets.QCalendarWidget(self)
        self.buttonNew = QtWidgets.QPushButton('New', self)
        self.buttonNew.clicked.connect(self.createNew)
        layout = QtWidgets.QVBoxLayout(self)
        layout.addWidget(self.devName)
        layout.addWidget(self.datePicker)
        layout.addWidget(self.buttonNew)

    def createNew(self):
        devname = self.devName.text()
        expdate = self.datePicker.selectedDate().toString("yyyy-MM-dd")
        print(username)
        print(password)
        print(devname)
        print(expdate)
        url = "https://wg.spoor.nu/new.php?user=" + username + "&pass=" + password + "&devname=" + devname + "&expdate=" + expdate
        r = requests.get(url)
        response = r.content.decode()
        
        if (response != "Fail!"):
            global config
            config = response
            self.accept()
        else:
            QtWidgets.QMessageBox.warning(
                self, 'Error', 'error occured')


class Show(QtWidgets.QDialog):
    def __init__(self, parent=None):
        super(Show, self).__init__(parent)
        self.config = QtWidgets.QLabel(config, self)
        self.save = QtWidgets.QPushButton('save to clipboard', self)
        self.save.clicked.connect(self.saveToClip)
        layout = QtWidgets.QVBoxLayout(self)
        layout.addWidget(self.config)
        layout.addWidget(self.save)

    def saveToClip(self):
        win32clipboard.OpenClipboard()
        win32clipboard.EmptyClipboard()
        win32clipboard.SetClipboardText(config)
        win32clipboard.CloseClipboard()

if __name__ == '__main__':

    import sys
    app = QtWidgets.QApplication(sys.argv)
    login = Login()

    if login.exec_() == QtWidgets.QDialog.Accepted:
        new = New()
        new.show()
        if new.exec_() == QtWidgets.QDialog.Accepted:
            show = Show()
            show.show()
            sys.exit(app.exec_())
