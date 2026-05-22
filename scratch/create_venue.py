import urllib.request
import json

def main():
    api_key = 'AIzaSyDS0KVNyhW5-3y72ojQo0SciuWp-iFPwTk'
    project_id = 'pingpongplayhub1'
    email = 'sala_test@playhub.com'
    password = 'password123'

    print(f"1. Se creeaza contul Firebase Auth pentru: {email}...")

    # Sign up endpoint
    signup_url = f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={api_key}"
    signup_data = json.dumps({
        "email": email,
        "password": password,
        "returnSecureToken": True
    }).encode('utf-8')

    req = urllib.request.Request(
        signup_url,
        data=signup_data,
        headers={'Content-Type': 'application/json'}
    )

    uid = None
    id_token = None

    try:
        with urllib.request.urlopen(req) as res:
            resp_data = json.loads(res.read().decode('utf-8'))
            uid = resp_data['localId']
            id_token = resp_data['idToken']
            print(f"Cont nou creat in Auth! UID: {uid}")
    except urllib.error.HTTPError as e:
        err_resp = json.loads(e.read().decode('utf-8'))
        error_message = err_resp.get('error', {}).get('message', '')
        if 'EMAIL_EXISTS' in error_message:
            print("Email-ul exista deja. Se logheaza pentru obtinerea token-ului...")
            # Sign in to get UID and Token
            signin_url = f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={api_key}"
            signin_data = json.dumps({
                "email": email,
                "password": password,
                "returnSecureToken": True
            }).encode('utf-8')

            req_signin = urllib.request.Request(
                signin_url,
                data=signin_data,
                headers={'Content-Type': 'application/json'}
            )
            try:
                with urllib.request.urlopen(req_signin) as res_signin:
                    resp_data = json.loads(res_signin.read().decode('utf-8'))
                    uid = resp_data['localId']
                    id_token = resp_data['idToken']
                    print(f"Logare reusita! UID: {uid}")
            except Exception as e_in:
                print(f"Eroare la logare: {e_in}")
                return
        else:
            print(f"Eroare Auth: {error_message}")
            return
    except Exception as e:
        print(f"Eroare generala Auth: {e}")
        return

    if not uid or not id_token:
        print("Nu s-a putut obtine UID sau ID Token.")
        return

    print("2. Se scrie documentul Firestore pentru sala...")

    firestore_url = f"https://firestore.googleapis.com/v1/projects/{project_id}/databases/(default)/documents/venues/{uid}"

    doc_data = {
        "fields": {
            "venueId": {"stringValue": uid},
            "venueName": {"stringValue": "Sala de Test Playhub"},
            "contactPerson": {"stringValue": "Administrator Test"},
            "phoneNumber": {"stringValue": "+40711223344"},
            "email": {"stringValue": email},
            "city": {"stringValue": "Bucuresti"},
            "address": {"stringValue": "Strada Ping Pong nr. 42"},
            "website": {"stringValue": "www.salatest-playhub.ro"},
            "indoorTables": {"integerValue": "6"},
            "outdoorTables": {"integerValue": "2"},
            "totalTables": {"integerValue": "8"},
            "facilities": {
                "arrayValue": {
                    "values": [
                        {"stringValue": "vestiare"},
                        {"stringValue": "aer_conditionat"},
                        {"stringValue": "inchiriere_palete"}
                    ]
                }
            },
            "pricePerHour": {"doubleValue": 20.0},
            "pricePerHourText": {"stringValue": "20 RON/ora"},
            "schedule": {
                "mapValue": {
                    "fields": {
                        "Luni-Vineri": {"stringValue": "08:00 - 22:00"},
                        "Sambata": {"stringValue": "09:00 - 20:00"},
                        "Duminica": {"stringValue": "10:00 - 18:00"}
                    }
                }
            },
            "cui": {"stringValue": "RO98765432"},
            "iban": {"stringValue": "RO99BTRLRONCRT9999999999"},
            "blockedDates": {
                "arrayValue": {}
            },
            "isVerified": {"booleanValue": True},
            "createdAt": {
                "timestampValue": "2026-05-22T09:44:00Z"
            }
        }
    }

    payload = json.dumps(doc_data).encode('utf-8')
    
    # Using PATCH to create or update
    req_firestore = urllib.request.Request(
        firestore_url,
        data=payload,
        headers={
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {id_token}'
        },
        method='PATCH'
    )

    try:
        with urllib.request.urlopen(req_firestore) as res_f:
            print("Sala salvata cu succes in Firestore!")
            print("Contul de test pentru sali este pregatit!")
            print(f"Email: {email}")
            print(f"Parola: {password}")
            print("Contul este marcat ca VERIFICAT, deci este complet functional!")
    except Exception as e:
        print(f"Eroare la scrierea in Firestore: {e}")

if __name__ == '__main__':
    main()
