import requests
import time

# 調査したい単語リスト（例）
words = [
    # A
    "absolu", "abstraction", "absurde", "académie", "accent", "acceptation", "accessoire", "accident", "accord", "accumulation", 
    "acte", "action", "actualité", "adaptation", "adhésion", "admiration", "affect", "affirmation", "agent", "agression", 
    "aide", "ailleurs", "aliénation", "allégorie", "alliance", "altérité", "ambiguïté", "ambition", "âme", "amitié", 
    "amour", "analogie", "analyse", "anarchie", "anatomie", "angoisse", "animal", "anomie", "anthropologie", "anticipation", 
    "antinomie", "antiquité", "apathie", "apparence", "appartenance", "application", "apprentissage", "appropriation", "approximatif", "arbitraire", 
    "archéologie", "architecture", "argument", "aristocratie", "art", "articulation", "artifice", "ascension", "aspect", "aspiration", 
    "assemblée", "assertion", "assimilation", "association", "assurance", "asymétrie", "atome", "attachement", "attaque", "attention", 
    "attitude", "attraction", "attribut", "au-delà", "audace", "augmentation", "authenticité", "autorité", "autonomie", "autrui", 
    "avance", "avenir", "aventure", "aveu", "axiome",
    
    # B - C
    "barbarie", "base", "beauté", "besoin", "bien", "bienveillance", "biographie", "biologie", "bonheur", "boucle", 
    "cadre", "calcul", "calme", "capacité", "capital", "caractère", "causalité", "cause", "célébration", "censure", 
    "certitude", "chair", "changement", "chaos", "charme", "choix", "chronologie", "cible", "cinéma", "circulation", 
    "citoyen", "civilisation", "clarté", "classe", "classique", "clivage", "code", "cogito", "cognition", "cohérence", 
    "cohésion", "coïncidence", "collectif", "combat", "combinaison", "comédie", "commencement", "commentaire", "commerce", "communication", 
    "communion", "comparaison", "compassion", "complexité", "complicité", "composition", "compréhension", "compromis", "concept", "conception", 
    "conclusion", "concrétisation", "concurrence", "condition", "conduite", "confession", "confiance", "conflit", "conformisme", "confrontation", 
    "confusion", "connaissance", "connoté", "conscience", "conséquence", "conservation", "considération", "consistance", "consolation", "constance", 
    "constant", "constitution", "construction", "contact", "contemplation", "contemporain", "contexte", "contingence", "continuité", "contradiction", 
    "contrainte", "contraste", "contrat", "contrôle", "convention", "convergence", "conversation", "conversion", "conviction", "coopération", 
    "coordination", "corps", "corpus", "corrélation", "correspondance", "cosmos", "courage", "coutume", "création", "créativité", 
    "crédit", "crise", "critique", "croyance", "cruauté", "culte", "culture", "curiosité", "cycle",
    
    # D - E
    "danger", "débat", "décadence", "décentrement", "déception", "décision", "déclaration", "décomposition", "déconstruction", "découverte", 
    "déduction", "défaut", "défense", "définition", "dégradation", "degré", "déjà-vu", "délire", "demande", "démocratie", 
    "démonstration", "dénégation", "dépendance", "dépense", "déplacement", "dépossession", "dérive", "dernier", "déroulement", "désaccord", 
    "désert", "déséquilibre", "désignation", "désir", "désordre", "dessein", "destin", "destruction", "détachement", "détail", 
    "détermination", "dette", "deuil", "devenir", "devoir", "dialectique", "dialogue", "dictature", "différence", "différend", 
    "diffusion", "dignité", "dimension", "direction", "discipline", "discontinuité", "discours", "discrétion", "discussion", "dispositif", 
    "disposition", "dispute", "dissolution", "distance", "distinction", "distribution", "diversité", "divinité", "division", "doctrine", 
    "document", "dogme", "domaine", "domination", "don", "douleur", "doute", "doxe", "drame", "droit", 
    "dualisme", "durée", "dynamique",
    "échange", "échec", "écho", "éclairage", "éclat", "école", "économie", "écriture", "éducation", "effectivité", 
    "effet", "efficacité", "effort", "égalités", "ego", "élaboration", "élan", "élément", "élection", "élégance", 
    "éloge", "émancipation", "émergence", "émotion", "empathie", "empirique", "emploi", "empreinte", "énergie", "engagement", 
    "énigme", "enjeu", "enlèvement", "ennui", "énoncé", "enquête", "enseignement", "ensemble", "enthousiasme", "entité", 
    "entrée", "entretien", "environnement", "envie", "épistémologie", "époque", "épreuve", "équilibre", "équité", "équivoque", 
    "ère", "erreur", "espace", "espèce", "espérance", "espoir", "esprit", "essence", "esthétique", "état", 
    "éternité", "éthique", "ethnie", "être", "étude", "événement", "évidence", "évolution", "exactitude", "exagération", 
    "examen", "excellence", "exception", "excès", "exclusion", "exécution", "exemple", "existence", "exigence", "exil", 
    "expansion", "expérience", "explication", "exploration", "exposition", "expression", "expropriation", "extension", "extériorité", "extinction"
]

API_URL = "https://minakata.lesure.net/api/v1/lexique"

def bulk_post(word_list):
    print(f"Starting investigation for {len(word_list)} words...")
    
    for i, word in enumerate(word_list):
        try:
            response = requests.post(
                API_URL, 
                json={"keyword": word},
                timeout=5
            )
            if response.status_code == 200:
                print(f"[{i+1}/{len(word_list)}] Accepted: {word}")
            else:
                print(f"[{i+1}/{len(word_list)}] Failed: {word} (Status: {response.status_code})")
        except Exception as e:
            print(f"[{i+1}/{len(word_list)}] Error: {word} ({str(e)})")
        
        # SQSやAPI Gatewayのレート制限を考慮し、わずかに間隔を空ける
        time.sleep(0.1)

if __name__ == "__main__":
    bulk_post(words)