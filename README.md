# notes-app

TypeScript note-taking app (Express + MongoDB driver), deployed to EKS behind an ALB,
talking to MongoDB running on an EC2 VM.

## MongoDB schema

None to create. MongoDB is schemaless and creates the `notesapp` database and the
`notes` collection on the first insert. The app creates one index (`createdAt: -1`)
at startup, which is idempotent.

The only manual DB step is the user, since the exercise requires authentication:

```js
// mongo shell, connected as the root user
use notesapp
db.createUser({
  user: "notesapp",
  pwd: "<password>",
  roles: [{ role: "readWrite", db: "notesapp" }]
})
```

## Build and push

```bash
npm install                      # local dev only, the image builds from package-lock.json
# --platform matters: an Apple Silicon build will not run on amd64 EKS nodes
docker build --platform linux/amd64 -t notes-app:v1 .
aws ecr get-login-password --region <REGION> | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com
docker tag notes-app:v1 <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/notes-app:v1
docker push <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/notes-app:v1
```

## Deploy

```bash
kubectl label node <node-name> app-node=notes-app          # pins the pod to one node
cp k8s/secret.example.yaml k8s/secret.yaml                 # fill in the real URI
kubectl apply -f k8s/secret.yaml
# edit k8s/app.yaml: image ref + MONGO_HOST (private IP of the mongo VM)
kubectl apply -f k8s/app.yaml
kubectl get ingress notes-app -w                           # wait for the ALB address
```

## Demo checklist

**wizexercise.txt is in the image** (it is `COPY`d in the final Dockerfile stage):

```bash
kubectl exec deploy/notes-app -- cat /app/wizexercise.txt
docker run --rm notes-app:v1 cat /app/wizexercise.txt      # same file, from the image
```

**Init container ran the netcat check first:**

```bash
kubectl logs deploy/notes-app -c wait-for-mongo
kubectl get pod -l app=notes-app -o jsonpath='{.items[0].spec.initContainers[0].image}'
```

**Pod is on the pinned node:**

```bash
kubectl get pods -l app=notes-app -o wide
```

**Mongo access is via an env var:**

```bash
kubectl exec deploy/notes-app -- printenv MONGODB_URI
```

**Pod has cluster-admin:**

```bash
kubectl auth can-i '*' '*' --all-namespaces \
  --as=system:serviceaccount:default:notes-app
```

**Data really is in the database** (add a note in the browser first):

```bash
ssh ec2-user@<mongo-vm>
# MongoDB 4.x ships the legacy `mongo` shell, mongosh is a separate install
mongo "mongodb://notesapp:<password>@localhost:27017/notesapp" \
  --eval 'printjson(db.notes.find().sort({createdAt:-1}).limit(5).toArray())'
```
