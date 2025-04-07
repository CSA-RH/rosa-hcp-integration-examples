const express = require('express');
const AWS = require('aws-sdk');
const bodyParser = require('body-parser');
const { DynamoDBClient, PutItemCommand } = require("@aws-sdk/client-dynamodb");
const { fromNodeProviderChain } = require("@aws-sdk/credential-providers");


// Initialize the Express app
const app = express();
const port = 3000;

// Body parser middleware to parse JSON payload
app.use(bodyParser.json());

// Initialize DynamoDB client (IAM role permissions are handled by IRSA in the pod)
const client = new DynamoDBClient({
    region: process.env.AWS_REGION || "us-east-1",
    credentials: fromNodeProviderChain({}) // This ensures the SDK uses IRSA
  });
const tableName = "Items"; // DynamoDB table name

// POST endpoint to add an item to DynamoDB
app.post('/item', async (req, res) => {
    const { id, data } = req.body;

    if (!id || !data) {
        return res.status(400).send({ error: 'Both id and data are required.' });
    }

    const params = {
        TableName: tableName,
        Item: {
            id: { S: id },
            data: { S: data },
            Timestamp: { S: new Date().toISOString() }
        }
    };

    try {
        const command = new PutItemCommand(params);
        await client.send(command);
        res.status(200).send({ message: 'Item added successfully!' });
    } catch (error) {
        console.error("Error adding item:", error);
        res.status(500).send({ error: 'Failed to add item.' });
    }
});


// Start the Express server
app.listen(port, () => {
    console.log(`Server is running on port ${port}`);
});